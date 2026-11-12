--!strict
--[[
	Signal: lightweight pure-Luau signal (no BindableEvent, no Roblox dependency).
	Handlers run synchronously in connection order; errors in one handler do not stop others.
]]

local Signal = {}
Signal.__index = Signal

export type Connection = { Connected: boolean, Disconnect: (Connection) -> () }
export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
	Destroy: (self: Signal<T...>) -> (),
}

type Handler = { fn: (...any) -> (), connected: boolean }

function Signal.new<T...>(): Signal<T...>
	local self = setmetatable({ _handlers = {} :: { Handler } }, Signal)
	return self :: any
end

function Signal.Connect(self: any, fn: (...any) -> ()): Connection
	local handler: Handler = { fn = fn, connected = true }
	table.insert(self._handlers, handler)
	local connection = {} :: any
	connection.Connected = true
	function connection.Disconnect(c: any)
		if not c.Connected then
			return
		end
		c.Connected = false
		handler.connected = false
		local index = table.find(self._handlers, handler)
		if index then
			table.remove(self._handlers, index)
		end
	end
	return connection
end

function Signal.Once(self: any, fn: (...any) -> ()): Connection
	local connection: Connection
	connection = Signal.Connect(self, function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function Signal.Fire(self: any, ...: any)
	-- Snapshot so handlers may disconnect while firing.
	local snapshot = table.clone(self._handlers)
	for _, handler in snapshot do
		if handler.connected then
			local ok, err = pcall(handler.fn, ...)
			if not ok then
				warn("[Signal] handler error: " .. tostring(err))
			end
		end
	end
end

function Signal.DisconnectAll(self: any)
	for _, handler in self._handlers do
		handler.connected = false
	end
	table.clear(self._handlers)
end

Signal.Destroy = Signal.DisconnectAll

return Signal
