--[[
	Test runner. From the repository root:
		lune run tests/run
	Runs every tests/*.spec.luau file and exits non-zero on failure.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local TestKit = require("./lib/testkit")

local files = {}
for _, name in fs.readDir("tests") do
	if name:match("%.spec%.luau$") then
		table.insert(files, name)
	end
end
table.sort(files)

for _, name in files do
	local moduleName = name:gsub("%.luau$", "")
	require("./" .. moduleName)
end

local passed, failed = TestKit.run()
print(string.format("\n%d passed, %d failed (%d files)", passed, failed, #files))
if failed > 0 then
	process.exit(1)
end
