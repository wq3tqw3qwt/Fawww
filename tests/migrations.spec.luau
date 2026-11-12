local Loader = require("./lib/loader")
local T = require("./lib/testkit")
local describe, it, expect = T.describe, T.it, T.expect

local Config = Loader.require("src/ReplicatedStorage/Shared/Config")
local DataTemplate = Loader.require("src/ReplicatedStorage/Shared/DataTemplate")
local Migrations = Loader.require("src/ReplicatedStorage/Shared/Migrations")

describe("Data template and migrations", function()
	it("template is at the current version with one owned line", function()
		local data = DataTemplate.Template()
		expect(data.Version).toBe(Config.DataVersion)
		expect(#data.Lines).toBe(1)
		expect(#data.Catalog.Stamps).toBe(#Config.Lines)
		expect(#data.Machines.Bays).toBe(Config.Expansion.BaysBase)
	end)

	it("templates are independent copies", function()
		local a = DataTemplate.Template()
		local b = DataTemplate.Template()
		a.Lines[1][1] = 99
		expect(b.Lines[1][1]).toBe(1)
	end)

	it("migrates v0 data: Gems -> Credits, fills missing keys, keeps progress", function()
		local legacy = {
			Cash = 5000,
			Gems = 40,
			Credits = 2,
			Lines = { { 7, 8, 9, 10 }, { 1, 1, 1, 1 } },
			Machines = { Inventory = {}, Bays = { "abc" } },
			Catalog = { Stamps = { 2 } },
		}
		local from = Migrations.Migrate(legacy)
		expect(from).toBe(0)
		expect(legacy.Version).toBe(Config.DataVersion)
		expect(legacy.Gems).toBe(nil)
		expect(legacy.Credits).toBe(42)
		expect(legacy.Cash).toBe(5000)
		expect(legacy.Lines[1][4]).toBe(10)
		expect(#legacy.Catalog.Stamps).toBe(#Config.Lines)
		expect(legacy.Catalog.Stamps[1]).toBe(2)
		expect(legacy.Machines.Bays[1]).toBe("abc")
		expect(legacy.Machines.Plating.Id).toBe("")
		expect(legacy.Stats.ProductsShipped).toBe(0)
		expect(legacy.Settings.Music).toBe(true)
	end)

	it("is idempotent for current-version data", function()
		local data = DataTemplate.Template()
		data.Cash = 123
		local from = Migrations.Migrate(data)
		expect(from).toBe(Config.DataVersion)
		expect(data.Cash).toBe(123)
	end)

	it("has a migration step for every version", function()
		for v = 1, Config.DataVersion do
			expect(Migrations.Steps[v] ~= nil).toBeTruthy()
		end
	end)
end)
