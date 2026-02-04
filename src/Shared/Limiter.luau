local Limiter = {}

local RunService = game:GetService("RunService")

-------------------------------------------------------------------------------
-- PRIVATE VARIABLES
-------------------------------------------------------------------------------

local debouncing: { [any]: number } = {}

-------------------------------------------------------------------------------
-- PUBLIC FUNCTIONS
-------------------------------------------------------------------------------

function Limiter.isDebouncing(key: any, duration: number)
	local timeNow = os.clock()

	local debounceUntil = debouncing[key]
	if debounceUntil and timeNow < debounceUntil then
		return true
	end

	debouncing[key] = timeNow + duration
	return false
end

-------------------------------------------------------------------------------
-- LOGIC
-------------------------------------------------------------------------------

local nextCleanupAt = 0
RunService.Heartbeat:Connect(function()
	local timeNow = os.clock()
	if timeNow < nextCleanupAt then
		return
	end

	-- Randomized interval so cleanup isn't constant
	nextCleanupAt = timeNow + math.random(50, 100) / 10

	for k, expireTime in next, debouncing do
		if expireTime <= timeNow then
			debouncing[k] = nil
		end
	end
end)

return Limiter
