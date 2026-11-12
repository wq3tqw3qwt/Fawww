--[[
	Lune module loader that emulates Roblox's `script` / `require(instance)` for the
	pure shared modules, so tests and the pacing simulation run the exact game code.

	Usage (from the repository root):
		local Loader = require("./lib/loader")
		local Formulas = Loader.require("src/ReplicatedStorage/Shared/Formulas")
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Loader = {}

local cache: { [string]: any } = {}
local proxyPaths = setmetatable({}, { __mode = "k" })

local function resolve(path: string): string?
	if fs.isFile(path .. ".luau") then
		return path .. ".luau"
	end
	if fs.isFile(path .. ".lua") then
		return path .. ".lua"
	end
	if fs.isDir(path) and fs.isFile(path .. "/init.luau") then
		return path .. "/init.luau"
	end
	return nil
end

local function parentOf(path: string): string
	return path:match("^(.*)/[^/]+$") or "."
end

local function makeProxy(instancePath: string)
	local proxy = setmetatable({}, {
		__index = function(_, key)
			if key == "Parent" then
				return makeProxy(parentOf(instancePath))
			elseif key == "Name" then
				return instancePath:match("([^/]+)$")
			elseif key == "WaitForChild" or key == "FindFirstChild" then
				return function(self, childName)
					return makeProxy(proxyPaths[self] .. "/" .. childName)
				end
			end
			return makeProxy(instancePath .. "/" .. key)
		end,
		__tostring = function()
			return instancePath
		end,
	})
	proxyPaths[proxy] = instancePath
	return proxy
end

local function stubGlobals()
	return {
		Color3 = roblox.Color3,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		UDim2 = roblox.UDim2,
		UDim = roblox.UDim,
		CFrame = roblox.CFrame,
		NumberRange = roblox.NumberRange,
		Enum = roblox.Enum,
	}
end

function Loader.require(path: string): any
	local file = resolve(path)
	assert(file, "Loader: cannot resolve module " .. path)
	if cache[file] ~= nil then
		return cache[file]
	end
	local source = fs.readFile(file)
	-- Strip the --!strict directive line-preserving; Lune does not need it.
	local instancePath = if file:match("/init%.luau$") then parentOf(file) else file:gsub("%.luau?$", "")
	local env = stubGlobals()
	env.script = makeProxy(instancePath)
	env.require = function(target)
		if type(target) == "string" then
			return require(target)
		end
		local targetPath = proxyPaths[target]
		assert(targetPath, "Loader: require() expects a script proxy")
		return Loader.require(targetPath)
	end
	local fn = luau.load(source, { debugName = file, environment = env })
	local result = fn()
	cache[file] = result
	return result
end

return Loader
