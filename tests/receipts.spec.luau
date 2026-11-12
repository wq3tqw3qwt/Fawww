local Loader = require("./lib/loader")
local T = require("./lib/testkit")
local describe, it, expect = T.describe, T.it, T.expect

local Ledger = Loader.require("src/ReplicatedStorage/Shared/ReceiptLedger")

-- Fake ProfileStore profile: Save() copies Data into LastSavedData, optionally failing.
local function fakeProfile()
	local profile = {
		active = true,
		data = { PurchaseIdCache = {} },
		saved = nil :: any,
		saveFailures = 0,
		saves = 0,
	}
	local adapter = {
		IsActive = function()
			return profile.active
		end,
		LiveCache = function()
			return profile.data.PurchaseIdCache
		end,
		SavedCache = function()
			return if profile.saved then profile.saved.PurchaseIdCache else nil
		end,
		SaveAndWait = function()
			profile.saves += 1
			if profile.saveFailures > 0 then
				profile.saveFailures -= 1
				return
			end
			profile.saved = { PurchaseIdCache = table.clone(profile.data.PurchaseIdCache) }
		end,
		RetryDelay = function(_seconds) end,
		MaxSize = 3,
	}
	return profile, adapter
end

describe("Receipt idempotency", function()
	it("grants once and returns PurchaseGranted after the save", function()
		local _, adapter = fakeProfile()
		local grants = 0
		local outcome = Ledger.Process(adapter, "P1", function()
			grants += 1
		end)
		expect(outcome).toBe("PurchaseGranted")
		expect(grants).toBe(1)
	end)

	it("a retried receipt (same PurchaseId) is never granted twice", function()
		local _, adapter = fakeProfile()
		local grants = 0
		local grant = function()
			grants += 1
		end
		Ledger.Process(adapter, "P1", grant)
		expect(Ledger.Process(adapter, "P1", grant)).toBe("PurchaseGranted")
		expect(Ledger.Process(adapter, "P1", grant)).toBe("PurchaseGranted")
		expect(grants).toBe(1)
	end)

	it("keeps retrying the save until the id is persisted", function()
		local profile, adapter = fakeProfile()
		profile.saveFailures = 2
		local grants = 0
		local outcome = Ledger.Process(adapter, "P2", function()
			grants += 1
		end)
		expect(outcome).toBe("PurchaseGranted")
		expect(grants).toBe(1)
		expect(profile.saves).toBe(3)
	end)

	it("returns NotProcessedYet when the session ends before saving, and does not regrant later", function()
		local profile, adapter = fakeProfile()
		local grants = 0
		adapter.SaveAndWait = function()
			profile.active = false
		end
		expect(Ledger.Process(adapter, "P3", function()
			grants += 1
		end)).toBe("NotProcessedYet")
		expect(grants).toBe(1)
		-- Same server session data still has the id cached: a retry only waits for the save.
		profile.active = true
		adapter.SaveAndWait = function()
			profile.saved = { PurchaseIdCache = table.clone(profile.data.PurchaseIdCache) }
		end
		expect(Ledger.Process(adapter, "P3", function()
			grants += 1
		end)).toBe("PurchaseGranted")
		expect(grants).toBe(1)
	end)

	it("a failing grant is not recorded, so Roblox retries it later", function()
		local _, adapter = fakeProfile()
		expect(Ledger.Process(adapter, "P4", function()
			error("boom")
		end)).toBe("NotProcessedYet")
		expect(Ledger.Has(adapter.LiveCache(), "P4")).toBeFalsy()
	end)

	it("evicts the oldest ids beyond the cache size", function()
		local cache = {}
		for i = 1, 5 do
			Ledger.Record(cache, "id" .. i, 3)
		end
		expect(#cache).toBe(3)
		expect(cache[1]).toBe("id3")
		Ledger.Record(cache, "id5", 3)
		expect(#cache).toBe(3)
	end)

	it("an inactive profile never grants", function()
		local profile, adapter = fakeProfile()
		profile.active = false
		local grants = 0
		expect(Ledger.Process(adapter, "P5", function()
			grants += 1
		end)).toBe("NotProcessedYet")
		expect(grants).toBe(0)
	end)
end)
