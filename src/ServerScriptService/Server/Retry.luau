--!strict
--[[
	Retry: pcall with exponential backoff for every DataStore / MemoryStore /
	MessagingService / MarketplaceService call.
]]

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local Retry = {}

-- Calls fn(...) until it succeeds or attempts run out. Returns (ok, result-or-error).
function Retry.Call<T...>(label: string, fn: (...any) -> T..., ...: any): (boolean, any)
	local settings = Config.Data.Retry
	local delay = settings.BaseDelaySeconds
	local lastError: any = nil
	for attempt = 1, settings.Attempts do
		local results = table.pack(pcall(fn, ...))
		if results[1] then
			return true, results[2]
		end
		lastError = results[2]
		if attempt < settings.Attempts then
			-- Jitter avoids synchronized retries across servers.
			task.wait(delay * (0.75 + math.random() * 0.5))
			delay = math.min(delay * 2, settings.MaxDelaySeconds)
		end
	end
	warn(string.format("[Retry] %s failed after %d attempts: %s", label, settings.Attempts, tostring(lastError)))
	return false, lastError
end

return Retry
