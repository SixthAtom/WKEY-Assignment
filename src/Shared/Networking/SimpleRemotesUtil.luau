local SimpleRemotesUtil = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Promise = require(ReplicatedStorage.Shared.Promise)
local BufferUtil = require(ReplicatedStorage.Shared.Util.BufferUtil)

local IS_SERVER = RunService:IsServer()

-------------------------------------------------------------------------------
-- TYPES
-------------------------------------------------------------------------------

type Action = string | number
type Actions = { [Action]: (...any) -> ...any }
type Deserializer = (...any) -> (Action, ...any)

type FunctionActions = {
	[Action]: (...any) -> ...any,
}

-------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS
-------------------------------------------------------------------------------

local function ActionsExecutor(actions: FunctionActions | Actions, action: Action, ...)
	action = tostring(action)

	local handler = actions[action] or actions[tonumber(action)]
	if handler then
		return handler(...)
	else
		warn("Action", action, "was not present in", actions)
	end
end

-------------------------------------------------------------------------------
-- PUBLIC VARIABLES
-------------------------------------------------------------------------------

SimpleRemotesUtil.DecodeActionBuffer = function(b: buffer)
	local remoteCode, offset = BufferUtil.readu8(b, 0)
	return remoteCode, BufferUtil.deallocate(b, 0, offset)
end

-------------------------------------------------------------------------------
-- PUBLIC FUNCTIONS
-------------------------------------------------------------------------------

function SimpleRemotesUtil.bindRemoteFunctionActions(
	remote: RemoteFunction,
	actions: Actions,
	deserializer: Deserializer?
)
	if IS_SERVER then
		remote.OnServerInvoke = function(player: Player, ...)
			local action: Action?
			local args = { ... }

			if deserializer then
				local deserialized = { deserializer(...) }
				action = deserialized[1]
				args = { unpack(deserialized, 2) }
			else
				action = args[1]
				table.remove(args, 1)
			end

			return ActionsExecutor(actions, action, player, unpack(args))
		end
	else
		remote.OnClientInvoke = function(...)
			local action: Action?
			local args = { ... }

			if deserializer then
				local deserialized = { deserializer(...) }
				action = deserialized[1]
				args = { unpack(deserialized, 2) }
			else
				action = args[1]
				table.remove(args, 1)
			end

			return ActionsExecutor(actions, action, unpack(args))
		end
	end
end

function SimpleRemotesUtil.bindRemoteEventActions(remote: RemoteEvent, actions: Actions, deserializer: Deserializer?)
	if IS_SERVER then
		return remote.OnServerEvent:Connect(function(player: Player, ...)
			local action: Action?
			local args = { ... }

			if deserializer then
				local deserialized = { deserializer(...) }
				action = deserialized[1]
				args = { unpack(deserialized, 2) }
			else
				action = args[1]
				table.remove(args, 1)
			end

			ActionsExecutor(actions, action, player, unpack(args))
		end)
	else
		return remote.OnClientEvent:Connect(function(...)
			local action: Action?
			local args = { ... }

			if deserializer then
				local deserialized = { deserializer(...) }
				action = deserialized[1]
				args = { unpack(deserialized, 2) }
			else
				action = args[1]
				table.remove(args, 1)
			end

			ActionsExecutor(actions, action, unpack(args))
		end)
	end
end

-------------------------------------------------------------------------------
-- LOGIC
-------------------------------------------------------------------------------

if IS_SERVER then
	function SimpleRemotesUtil.fireActionToAllClients(remote: RemoteEvent, action: Action, ...)
		remote:FireAllClients(action, ...)
	end

	function SimpleRemotesUtil.fireActionToClient(client: Player, remote: RemoteEvent, action: Action, ...)
		remote:FireClient(client, action, ...)
	end
else
	function SimpleRemotesUtil.fireActionToServer(remote: RemoteEvent, action: Action, ...)
		remote:FireServer(action, ...)
	end

	function SimpleRemotesUtil.invokeActionToServer(remote: RemoteFunction, action: Action, ...)
		return remote:InvokeServer(action, ...)
	end

	function SimpleRemotesUtil.invokeActionToServerAsync(remote: RemoteFunction, action: Action, ...)
		local args = table.pack(...)

		return Promise.new(function(resolve, reject)
			local result =
				table.pack(pcall(SimpleRemotesUtil.invokeActionToServer, remote, action, unpack(args, 1, args.n)))

			if result[1] then
				resolve(unpack(result, 2, result.n))
			else
				reject(result[2])
			end
		end)
	end
end

return SimpleRemotesUtil
