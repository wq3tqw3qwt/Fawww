--!strict
--[[
	Maid: tracks connections, instances, threads and cleanup callbacks and releases them
	together. Every controller/service that connects to signals owns a Maid.
]]

local Maid = {}
Maid.__index = Maid

export type Task = RBXScriptConnection | Instance | thread | () -> () | { Destroy: (any) -> () } | { Disconnect: (any) -> () }
export type Maid = typeof(setmetatable({} :: { _tasks: { [any]: Task } }, Maid))

function Maid.new(): Maid
	return setmetatable({ _tasks = {} }, Maid)
end

local function cleanup(task: any)
	local kind = typeof(task)
	if kind == "RBXScriptConnection" then
		task:Disconnect()
	elseif kind == "Instance" then
		task:Destroy()
	elseif kind == "thread" then
		if coroutine.status(task) ~= "dead" then
			pcall(task.cancel, task)
		end
	elseif kind == "function" then
		task()
	elseif type(task) == "table" then
		if type(task.Destroy) == "function" then
			task:Destroy()
		elseif type(task.Disconnect) == "function" then
			task:Disconnect()
		end
	end
end

-- Adds a task and returns it (handy for inline use).
function Maid.Add<T>(self: Maid, task: T): T
	table.insert(self._tasks :: any, task)
	return task
end

-- Stores a task under a key, cleaning up any previous task with that key.
function Maid.Set(self: Maid, key: string, task: Task?)
	local old = self._tasks[key]
	if old ~= nil and old ~= task then
		cleanup(old)
	end
	self._tasks[key] = task :: any
end

function Maid.Remove(self: Maid, key: string)
	self:Set(key, nil)
end

function Maid.Clean(self: Maid)
	local tasks = self._tasks
	self._tasks = {}
	for _, task in tasks do
		cleanup(task)
	end
end

Maid.Destroy = Maid.Clean

return Maid
