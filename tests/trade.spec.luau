local Loader = require("./lib/loader")
local T = require("./lib/testkit")
local describe, it, expect = T.describe, T.it, T.expect

local Config = Loader.require("src/ReplicatedStorage/Shared/Config")
local TradeLogic = Loader.require("src/ReplicatedStorage/Shared/TradeLogic")

local function item(id: string, grade: number?, locked: boolean?)
	return { Id = id, Grade = grade or 0, Locked = locked or false, At = 0 }
end

local function fixtures()
	local invA = {
		a1 = item("rivet_bot"),
		a2 = item("titan_forge", 1),
		a3 = item("golden_robot"), -- pass machine: untradable
		a4 = item("spark_welder", 0, true), -- locked
		a5 = item("furnace_golem"), -- equipped
	}
	local invB = {
		b1 = item("solder_drone"),
		b2 = item("mainframe_prime"),
	}
	return invA, TradeLogic.EquippedSet({ "a5", "" }), invB, TradeLogic.EquippedSet({ "" })
end

local function keys(inv)
	local list = {}
	for k in inv do
		table.insert(list, k)
	end
	table.sort(list)
	return table.concat(list, ",")
end

describe("Trade validation and execution", function()
	it("swaps offered machines and keeps their uids", function()
		local invA, eqA, invB, eqB = fixtures()
		local ok = TradeLogic.Execute(invA, eqA, { "a1", "a2" }, invB, eqB, { "b2" })
		expect(ok).toBeTruthy()
		expect(invA.a1).toBe(nil)
		expect(invB.a1.Id).toBe("rivet_bot")
		expect(invB.a2.Grade).toBe(1)
		expect(invA.b2.Id).toBe("mainframe_prime")
	end)

	it("rejects duplicate uids in one offer (dupe attempt)", function()
		local invA, eqA = fixtures()
		local ok, err = TradeLogic.ValidateOffer(invA, eqA, { "a1", "a1" })
		expect(ok).toBeFalsy()
		expect(err).toBe("Duplicate item")
	end)

	it("rejects equipped, locked, untradable and unowned machines", function()
		local invA, eqA = fixtures()
		expect((TradeLogic.ValidateOffer(invA, eqA, { "a5" }))).toBeFalsy()
		expect((TradeLogic.ValidateOffer(invA, eqA, { "a4" }))).toBeFalsy()
		expect((TradeLogic.ValidateOffer(invA, eqA, { "a3" }))).toBeFalsy()
		expect((TradeLogic.ValidateOffer(invA, eqA, { "zz" }))).toBeFalsy()
	end)

	it("rejects malformed offers from the client", function()
		local invA, eqA = fixtures()
		expect((TradeLogic.ValidateOffer(invA, eqA, "a1"))).toBeFalsy()
		expect((TradeLogic.ValidateOffer(invA, eqA, { x = "a1" }))).toBeFalsy()
		expect((TradeLogic.ValidateOffer(invA, eqA, { 5 }))).toBeFalsy()
		expect((TradeLogic.ValidateOffer(invA, eqA, { string.rep("a", 200) }))).toBeFalsy()
	end)

	it("rejects more than MaxItemsPerSide items", function()
		local inv = {}
		local offer = {}
		for i = 1, Config.Trade.MaxItemsPerSide + 1 do
			inv["u" .. i] = item("rivet_bot")
			table.insert(offer, "u" .. i)
		end
		expect((TradeLogic.ValidateOffer(inv, {}, offer))).toBeFalsy()
	end)

	it("is atomic: a failed validation leaves both inventories untouched", function()
		local invA, eqA, invB, eqB = fixtures()
		local beforeA, beforeB = keys(invA), keys(invB)
		local ok = TradeLogic.Execute(invA, eqA, { "a1" }, invB, eqB, { "b1", "missing" })
		expect(ok).toBeFalsy()
		expect(keys(invA)).toBe(beforeA)
		expect(keys(invB)).toBe(beforeB)
	end)

	it("refuses when an item already exists on both sides (duplication guard)", function()
		local invA, eqA, invB, eqB = fixtures()
		invB.a1 = item("rivet_bot")
		local ok, err = TradeLogic.Execute(invA, eqA, { "a1" }, invB, eqB, {})
		expect(ok).toBeFalsy()
		expect(err).toBe("Item conflict")
	end)

	it("cannot execute twice: second run fails because items moved", function()
		local invA, eqA, invB, eqB = fixtures()
		expect((TradeLogic.Execute(invA, eqA, { "a1" }, invB, eqB, { "b1" }))).toBeTruthy()
		expect((TradeLogic.Execute(invA, eqA, { "a1" }, invB, eqB, { "b1" }))).toBeFalsy()
	end)

	it("refuses empty trades and full inventories", function()
		local invA, eqA, invB, eqB = fixtures()
		expect((TradeLogic.Execute(invA, eqA, {}, invB, eqB, {}))).toBeFalsy()
		local big = {}
		for i = 1, Config.MachineGrades.InventoryLimit do
			big["x" .. i] = item("rivet_bot")
		end
		local ok, err = TradeLogic.Execute(big, {}, {}, invB, eqB, { "b1" })
		expect(ok).toBeFalsy()
		expect(err).toBe("Inventory full")
	end)

	it("flags lopsided trades by Power ratio", function()
		local invA, _, invB = fixtures()
		local pA = TradeLogic.OfferPower(invA, { "a1" }) -- 10
		local pB = TradeLogic.OfferPower(invB, { "b2" }) -- 450
		expect(TradeLogic.IsLopsided(pA, pB)).toBeTruthy()
		expect(TradeLogic.IsLopsided(100, 120)).toBeFalsy()
	end)
end)
