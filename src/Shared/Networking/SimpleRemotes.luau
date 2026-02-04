--!strict

local SimpleRemotes = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local InstanceUtil = require(ReplicatedStorage.Shared.Util.InstanceUtil)

local IS_SERVER = RunService:IsServer()

-------------------------------------------------------------------------------
-- PRIVATE VARIABLES
-------------------------------------------------------------------------------

local communicationFolder: Folder
local unreliableFolder: Folder
local eventFolder: Folder
local functionFolder: Folder

-------------------------------------------------------------------------------
-- PUBLIC FUNCTIONS
-------------------------------------------------------------------------------

--- Creates or gets an UnreliableRemoteEvent
function SimpleRemotes.getUnreliableEvent(name: string): UnreliableRemoteEvent
	if not IS_SERVER then
		return unreliableFolder:WaitForChild(name) :: UnreliableRemoteEvent
	end

	local existing = unreliableFolder:FindFirstChild(name)
	if existing then
		return existing :: UnreliableRemoteEvent
	end

	local remote = Instance.new("UnreliableRemoteEvent")
	remote.Name = name
	remote.Parent = unreliableFolder
	return remote
end

--- Creates or gets a RemoteEvent
function SimpleRemotes.getEvent(name: string): RemoteEvent
	if not IS_SERVER then
		return eventFolder:WaitForChild(name) :: RemoteEvent
	end

	local existing = eventFolder:FindFirstChild(name)
	if existing then
		return existing :: RemoteEvent
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = eventFolder
	return remote
end

--- Creates or gets a RemoteFunction
function SimpleRemotes.getFunction(name: string): RemoteFunction
	if not IS_SERVER then
		return functionFolder:WaitForChild(name) :: RemoteFunction
	end

	local existing = functionFolder:FindFirstChild(name)
	if existing then
		return existing :: RemoteFunction
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = functionFolder
	return remote
end

-------------------------------------------------------------------------------
-- LOGIC
-------------------------------------------------------------------------------

if IS_SERVER then
	communicationFolder = InstanceUtil.newNameParent("Folder", "__SIMPLEREMOTES", ReplicatedStorage) :: Folder
	unreliableFolder = InstanceUtil.newNameParent("Folder", "UnreliableEvents", communicationFolder) :: Folder
	eventFolder = InstanceUtil.newNameParent("Folder", "Events", communicationFolder) :: Folder
	functionFolder = InstanceUtil.newNameParent("Folder", "Functions", communicationFolder) :: Folder
else
	communicationFolder = ReplicatedStorage:WaitForChild("__SIMPLEREMOTES") :: Folder
	unreliableFolder = communicationFolder:WaitForChild("UnreliableEvents") :: Folder
	eventFolder = communicationFolder:WaitForChild("Events") :: Folder
	functionFolder = communicationFolder:WaitForChild("Functions") :: Folder
end

return SimpleRemotes
