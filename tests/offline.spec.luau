local Loader = require("./lib/loader")
local T = require("./lib/testkit")
local describe, it, expect = T.describe, T.it, T.expect

local Config = Loader.require("src/ReplicatedStorage/Shared/Config")
local F = Loader.require("src/ReplicatedStorage/Shared/Formulas")

describe("Offline earnings", function()
	it("pays nothing below the minimum absence", function()
		local cash = F.OfflineEarnings(Config.Offline.MinSeconds - 1, 1000, 2, 0.2)
		expect(cash).toBe(0)
	end)

	it("pays time * income * efficiency", function()
		local cash, seconds = F.OfflineEarnings(3600, 1000, 2, 0.2)
		expect(seconds).toBe(3600)
		expect(cash).toBe(3600 * 1000 * 0.2)
	end)

	it("caps credited time at the cap", function()
		local cash, seconds = F.OfflineEarnings(10 * 3600, 1000, 2, 0.2)
		expect(seconds).toBe(7200)
		expect(cash).toBe(7200 * 1000 * 0.2)
	end)

	it("cap hours: base 2h, research adds, pass doubles", function()
		expect(F.OfflineCapHours(0, false)).toBe(2)
		expect(F.OfflineCapHours(4, false)).toBe(6)
		expect(F.OfflineCapHours(4, true)).toBe(12)
	end)

	it("pays nothing when income is zero", function()
		expect((F.OfflineEarnings(5000, 0, 2, 0.2))).toBe(0)
	end)
end)
