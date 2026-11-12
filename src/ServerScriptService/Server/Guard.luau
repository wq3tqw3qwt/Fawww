--!strict
--[[
	Guard: argument validators for remote handlers. Each returns the typed value or nil.
	Never trust client input: types, ranges, integer-ness, string length, NaN/inf.
]]

local Guard = {}

function Guard.Number(x: any, min: number, max: number): number?
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return nil
	end
	if x < min or x > max then
		return nil
	end
	return x
end

function Guard.Integer(x: any, min: number, max: number): number?
	local n = Guard.Number(x, min, max)
	if n == nil or n ~= math.floor(n) then
		return nil
	end
	return n
end

function Guard.String(x: any, maxLength: number): string?
	if type(x) ~= "string" or #x == 0 or #x > maxLength then
		return nil
	end
	return x
end

function Guard.Boolean(x: any): boolean?
	if type(x) ~= "boolean" then
		return nil
	end
	return x
end

-- Key must exist in the given dictionary (e.g. Config.GamePasses).
function Guard.Key<T>(x: any, dictionary: { [string]: T }): string?
	if type(x) ~= "string" or #x > 64 or dictionary[x] == nil then
		return nil
	end
	return x
end

-- Array of strings with no holes, bounded length.
function Guard.StringArray(x: any, maxItems: number, maxLength: number): { string }?
	if type(x) ~= "table" then
		return nil
	end
	local out = {}
	local count = 0
	for key, value in x do
		count += 1
		if type(key) ~= "number" or key ~= count or count > maxItems then
			return nil
		end
		if type(value) ~= "string" or #value == 0 or #value > maxLength then
			return nil
		end
		out[count] = value
	end
	return out
end

-- Array of integers in [min, max], bounded length.
function Guard.IntegerArray(x: any, maxItems: number, min: number, max: number): { number }?
	if type(x) ~= "table" then
		return nil
	end
	local out = {}
	local count = 0
	for key, value in x do
		count += 1
		if type(key) ~= "number" or key ~= count or count > maxItems then
			return nil
		end
		local n = Guard.Integer(value, min, max)
		if n == nil then
			return nil
		end
		out[count] = n
	end
	return out
end

return Guard
