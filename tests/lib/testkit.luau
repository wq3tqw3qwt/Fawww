--[[
	Tiny test framework for Lune: describe / it / expect.
]]

local TestKit = {}

type Case = { name: string, fn: () -> () }
type Suite = { name: string, cases: { Case } }

local suites: { Suite } = {}
local current: Suite? = nil

function TestKit.describe(name: string, body: () -> ())
	local suite = { name = name, cases = {} }
	table.insert(suites, suite)
	local previous = current
	current = suite
	body()
	current = previous
end

function TestKit.it(name: string, fn: () -> ())
	assert(current, "it() must be inside describe()")
	table.insert(current.cases, { name = name, fn = fn })
end

local function fail(message: string)
	error(message, 3)
end

function TestKit.expect(actual: any)
	local e = {}
	function e.toBe(expected: any)
		if actual ~= expected then
			fail(string.format("expected %s to be %s", tostring(actual), tostring(expected)))
		end
	end
	function e.toBeCloseTo(expected: number, relTol: number?)
		local tol = relTol or 1e-9
		local diff = math.abs(actual - expected)
		if diff > tol * math.max(1, math.abs(expected)) then
			fail(string.format("expected %s to be close to %s", tostring(actual), tostring(expected)))
		end
	end
	function e.toBeTruthy()
		if not actual then
			fail("expected value to be truthy, got " .. tostring(actual))
		end
	end
	function e.toBeFalsy()
		if actual then
			fail("expected value to be falsy, got " .. tostring(actual))
		end
	end
	function e.toBeGreaterThan(n: number)
		if not (actual > n) then
			fail(string.format("expected %s > %s", tostring(actual), tostring(n)))
		end
	end
	function e.toBeLessThan(n: number)
		if not (actual < n) then
			fail(string.format("expected %s < %s", tostring(actual), tostring(n)))
		end
	end
	function e.toBeAtMost(n: number)
		if not (actual <= n) then
			fail(string.format("expected %s <= %s", tostring(actual), tostring(n)))
		end
	end
	function e.toThrow()
		local ok = pcall(actual)
		if ok then
			fail("expected function to throw")
		end
	end
	return e
end

-- Runs every registered suite; returns (passed, failed).
function TestKit.run(): (number, number)
	local passed, failed = 0, 0
	for _, suite in suites do
		print("\n" .. suite.name)
		for _, case in suite.cases do
			local ok, err = pcall(case.fn)
			if ok then
				passed += 1
				print("  [PASS] " .. case.name)
			else
				failed += 1
				print("  [FAIL] " .. case.name .. "\n         " .. tostring(err))
			end
		end
	end
	table.clear(suites)
	return passed, failed
end

return TestKit
