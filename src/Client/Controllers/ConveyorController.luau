local ConveyorController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BufferConstants = require(ReplicatedStorage.Shared.Constants.BufferConstants)
local ConveyorConstants = require(ReplicatedStorage.Shared.Constants.ConveyorConstants)
local RemoteCodes = require(ReplicatedStorage.Shared.Networking.RemoteCodes)
local SimpleRemotes = require(ReplicatedStorage.Shared.Networking.SimpleRemotes)
local BufferUtil = require(ReplicatedStorage.Shared.Util.BufferUtil)

-------------------------------------------------------------------------------
-- CONSTANTS
-------------------------------------------------------------------------------

local REMOTE_CODES = RemoteCodes.Conveyor
local INTERVAL_RATES = ConveyorConstants.IntervalRates
local BYTE_SIZES = BufferConstants.Sizes

-------------------------------------------------------------------------------
-- PRIVATE VARIABLES
-------------------------------------------------------------------------------

local player = Players.LocalPlayer

local controlScreen = player.PlayerGui.ConveyorControl

local conveyorRemoteEvent = SimpleRemotes.getEvent("Conveyor")

-------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS
-------------------------------------------------------------------------------

-- Updates the controlUI to match current game state
-- Called whenever ownership or interval attributes change
local function updateControlScreen()
	-- Visibility is determined by a player attribute set by the server
	local visible = player:GetAttribute("ConveyorsOwner") == true

	-- Interval is stored in ReplicatedStorage for easy access
	local intervalAmount = ReplicatedStorage:GetAttribute("ConveyorInterval")

	controlScreen.Enabled = visible
	controlScreen.Frame.TextLabel.Text = `Current Interval: {intervalAmount}`
end

-------------------------------------------------------------------------------
-- CORE FUNCTIONS
-------------------------------------------------------------------------------

function ConveyorController.init()
	controlScreen.Enabled = false -- Disabled by default
	updateControlScreen() -- Initialize so screen is in sync

	-- Load the screen regardless of it's visibility
	local submitButton = controlScreen.Frame.Submit
	local intervalTextBox = controlScreen.Frame.TextBox

	submitButton.MouseButton1Click:Connect(function()
		local input = intervalTextBox.Text
		intervalTextBox.Text = "" -- Clear textbox immediately so player gets instant feedback

		input = tonumber(input) -- convert to number and verify it actually is numeric
		if not input then
			warn("Not a number")
			return
		end

		if input < INTERVAL_RATES.Min then
			warn(`Interval too low, {INTERVAL_RATES.Min} = min`)
			return
		end

		if input > INTERVAL_RATES.Max then
			warn(`Interval too high, {INTERVAL_RATES.Max} = max `)
			return
		end

		-- Pack into a buffer to keep network payload small and consistent with the rest of my networking code
		local b, offset = buffer.create(BYTE_SIZES.u8 + BYTE_SIZES.f32), 0
		offset = BufferUtil.writeu8(b, offset, REMOTE_CODES.Events.SetInterval)
		offset = BufferUtil.writef32(b, offset, input)

		conveyorRemoteEvent:FireServer(b)
	end)
end

-------------------------------------------------------------------------------
-- LOGIC
-------------------------------------------------------------------------------

-- UI reacts to attribute changes instead of polling values
-- This ensures an instant update with no manual refresh logic
ReplicatedStorage:GetAttributeChangedSignal("ConveyorInterval"):Connect(updateControlScreen)
player:GetAttributeChangedSignal("ConveyorsOwner"):Connect(updateControlScreen)

return ConveyorController
