local PlayersUtil = {}

local Players = game:GetService("Players")

-------------------------------------------------------------------------------
-- PUBLIC FUNCTIONS
-------------------------------------------------------------------------------

function PlayersUtil.connectEvents(handlers: {
	PlayerJoined: ((player: Player) -> ())?,
	PlayerLeft: ((player: Player) -> ())?,
})
	local connections: { RBXScriptConnection } = {}
	if handlers.PlayerJoined then
		for _, plr in Players:GetPlayers() do
			task.spawn(handlers.PlayerJoined, plr)
		end
		table.insert(connections, Players.PlayerAdded:Connect(handlers.PlayerJoined))
	end

	if handlers.PlayerLeft then
		table.insert(connections, Players.PlayerRemoving:Connect(handlers.PlayerLeft))
	end
	return connections
end

return PlayersUtil
