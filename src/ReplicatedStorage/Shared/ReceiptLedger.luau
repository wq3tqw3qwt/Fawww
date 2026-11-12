--!strict
--[[
	ReceiptLedger: idempotency bookkeeping for MarketplaceService.ProcessReceipt.

	Follows the ProfileStore-recommended flow:
	1. If the PurchaseId is not in the live cache, grant the product and record the id.
	2. Return PurchaseGranted only once the id appears in Profile.LastSavedData (saved).
	A retried receipt (same PurchaseId) is never granted twice.
]]

local ReceiptLedger = {}

export type Decision = "Grant" | "AwaitSave" | "AlreadySaved"

function ReceiptLedger.Has(cache: { string }?, purchaseId: string): boolean
	return cache ~= nil and table.find(cache, purchaseId) ~= nil
end

-- Records the id, evicting the oldest entries beyond `maxSize`.
function ReceiptLedger.Record(cache: { string }, purchaseId: string, maxSize: number)
	if table.find(cache, purchaseId) then
		return
	end
	while #cache >= maxSize do
		table.remove(cache, 1)
	end
	table.insert(cache, purchaseId)
end

-- What to do with a receipt given the live and last-saved caches.
function ReceiptLedger.Decide(liveCache: { string }?, savedCache: { string }?, purchaseId: string): Decision
	if ReceiptLedger.Has(savedCache, purchaseId) then
		return "AlreadySaved"
	end
	if ReceiptLedger.Has(liveCache, purchaseId) then
		return "AwaitSave"
	end
	return "Grant"
end

export type Adapter = {
	IsActive: () -> boolean,
	LiveCache: () -> { string },
	SavedCache: () -> { string }?,
	-- Requests a save and yields until it completes (or the session ends).
	SaveAndWait: () -> (),
	-- Pause between save attempts (seconds); tests pass 0.
	RetryDelay: (seconds: number) -> (),
	MaxSize: number,
}

export type Outcome = "PurchaseGranted" | "NotProcessedYet"

-- Full idempotent receipt flow. `grant` runs at most once per PurchaseId per profile.
function ReceiptLedger.Process(adapter: Adapter, purchaseId: string, grant: () -> ()): Outcome
	if not adapter.IsActive() then
		return "NotProcessedYet"
	end
	local decision = ReceiptLedger.Decide(adapter.LiveCache(), adapter.SavedCache(), purchaseId)
	if decision == "AlreadySaved" then
		return "PurchaseGranted"
	end
	if decision == "Grant" then
		local ok, err = pcall(function(): any
			grant()
			return nil
		end)
		if not ok then
			warn("[ReceiptLedger] grant failed for " .. purchaseId .. ": " .. tostring(err))
			return "NotProcessedYet"
		end
		ReceiptLedger.Record(adapter.LiveCache(), purchaseId, adapter.MaxSize)
	end
	-- Wait until the purchase id is confirmed saved.
	while adapter.IsActive() do
		adapter.SaveAndWait()
		if ReceiptLedger.Has(adapter.SavedCache(), purchaseId) then
			return "PurchaseGranted"
		end
		if adapter.IsActive() then
			adapter.RetryDelay(10)
		end
	end
	return "NotProcessedYet"
end

return ReceiptLedger
