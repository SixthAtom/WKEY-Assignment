--[[
	These I use in remotes so they're easily bufferized
]]

export type Code = number

return {
	Conveyor = {
		Events = {
			SetInterval = 1,
		},
	},

	Bags = {
		Events = {
			Spawn = 1,
			Clicked = 2,
		},

		Functions = {
			Get = 1,
		},
	},
}
