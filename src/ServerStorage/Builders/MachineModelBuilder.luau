--!strict
--[[
	MachineModelBuilder: procedural models for specialist machines (Build) and the four
	production-line stages (BuildStage). Shapes are authored on a 4-stud footprint and scaled by
	Config.Visuals.Machine.Footprint; every colour and material comes from the machine definition or Config.

	Machine models: pivot = bottom centre of the base plate, front = -Z, ~4 studs wide, up to ~5.5 tall.
	Stage models:   pivot = floor centre of the stage footprint (9 x 11 studs), belt axis = X.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildKit = require(script.Parent.BuildKit)
local Config = require(ReplicatedStorage.Shared.Config)

local MachineModelBuilder = {}

type Role = "P" | "S" | "N" | "G" | "D"

type Kit = {
	-- role, x, y, z, sizeX, sizeY, sizeZ, rotation
	b: (Role, number, number, number, number, number, number, CFrame?) -> Part,
	-- role, x, y, z, diameter, length (along axis), axis ("X" | "Y" | "Z"), rotation
	c: (Role, number, number, number, number, number, string?, CFrame?) -> Part,
	-- role, x, y, z, diameter
	o: (Role, number, number, number, number) -> Part,
	-- role, x, y, z, sizeX, sizeY, sizeZ, rotation
	w: (Role, number, number, number, number, number, number, CFrame?) -> WedgePart,
}

local function rot(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

local function at(x: number, y: number, z: number, r: CFrame?): CFrame
	local cf = CFrame.new(x, y, z)
	if r then
		cf = cf * r
	end
	return cf
end

--------------------------------------------------------------------------------
-- Machine shapes (4-stud footprint, y up from the plate top at 0.3, front = -Z)
--------------------------------------------------------------------------------
local function arm(k: Kit, ox: number, s: number)
	k.c("D", ox, 0.6, 0, 2 * s, 0.6)
	k.c("P", ox, 1.2, 0, 1.3 * s, 0.9)
	k.b("P", ox + 0.5 * s, 2.5, 0, 0.7 * s, 2.5, 0.7 * s, rot(0, 0, -22))
	k.o("N", ox + 1.0 * s, 3.7, 0, 0.9 * s)
	k.b("S", ox + 1.0 * s, 3.9, -1.2 * s, 0.6 * s, 0.6 * s, 2.3 * s, rot(20, 0, 0))
	k.b("D", ox + 0.7 * s, 3.2, -2.3 * s, 0.25, 0.9, 0.25)
	k.b("D", ox + 1.3 * s, 3.2, -2.3 * s, 0.25, 0.9, 0.25)
end

local SHAPES: { [string]: (Kit) -> () } = {
	CubeBot = function(k)
		k.b("S", -0.7, 0.7, 0, 0.8, 0.8, 0.8)
		k.b("S", 0.7, 0.7, 0, 0.8, 0.8, 0.8)
		k.b("P", 0, 2.1, 0, 2.4, 2, 2.4)
		k.b("N", 0, 2.1, -1.22, 1, 0.5, 0.1)
		k.b("S", 0, 3.65, 0, 1.6, 1.1, 1.6)
		k.b("N", -0.4, 3.7, -0.82, 0.35, 0.35, 0.15)
		k.b("N", 0.4, 3.7, -0.82, 0.35, 0.35, 0.15)
		k.b("S", -1.5, 2.1, 0, 0.5, 1.4, 0.7)
		k.b("S", 1.5, 2.1, 0, 0.5, 1.4, 0.7)
		k.c("S", 0, 4.6, 0, 0.15, 0.8)
		k.o("N", 0, 5.1, 0, 0.35)
	end,
	HexBot = function(k)
		for i = 0, 5 do
			local a = math.rad(i * 60)
			k.b("S", math.cos(a) * 1.4, 0.7, math.sin(a) * 1.4, 0.7, 0.8, 0.7, rot(0, -i * 60, 0))
		end
		k.c("P", 0, 1.9, 0, 2.8, 1.8)
		k.c("N", 0, 1.9, 0, 3, 0.2)
		k.o("S", 0, 2.8, 0, 2.4)
		k.o("N", 0, 2.9, -1.0, 0.7)
		k.c("S", 0, 4.3, 0, 0.15, 0.8)
		k.o("N", 0, 4.8, 0, 0.35)
	end,
	Arm = function(k)
		arm(k, -0.4, 1)
	end,
	TwinArm = function(k)
		arm(k, -1.3, 0.6)
		arm(k, 0.8, 0.6)
	end,
	Press = function(k)
		for _, x in { -1.5, 1.5 } do
			for _, z in { -1.2, 1.2 } do
				k.b("S", x, 2.1, z, 0.5, 3.6, 0.5)
			end
		end
		k.b("D", 0, 0.7, 0, 2.6, 0.8, 2.2)
		k.b("P", 0, 4.2, 0, 3.6, 0.9, 3)
		k.c("D", 0, 3.4, 0, 0.7, 1.3)
		k.b("P", 0, 2.6, 0, 2, 0.4, 2)
		k.b("N", 0, 2.6, -1.02, 1.6, 0.1, 0.1)
	end,
	Golem = function(k)
		k.b("P", -0.7, 0.9, 0, 0.9, 1.2, 0.9)
		k.b("P", 0.7, 0.9, 0, 0.9, 1.2, 0.9)
		k.b("P", 0, 2.5, 0, 2.4, 2, 1.8)
		k.o("S", -1.5, 3.3, 0, 1.1)
		k.o("S", 1.5, 3.3, 0, 1.1)
		k.b("P", -1.6, 2.1, 0, 0.9, 2, 0.9)
		k.b("P", 1.6, 2.1, 0, 0.9, 2, 0.9)
		k.b("S", -1.6, 0.95, -0.1, 1.1, 1.1, 1.1)
		k.b("S", 1.6, 0.95, -0.1, 1.1, 1.1, 1.1)
		k.b("S", 0, 4.0, 0, 1.2, 1, 1.1)
		k.b("N", -0.3, 4.05, -0.58, 0.25, 0.2, 0.1)
		k.b("N", 0.3, 4.05, -0.58, 0.25, 0.2, 0.1)
		k.b("N", 0, 2.6, -0.93, 0.9, 0.9, 0.1)
		k.b("S", -1.2, 3.8, 0.2, 0.5, 0.5, 0.5, rot(20, 30, 10))
		k.b("S", 1.1, 3.9, -0.2, 0.4, 0.4, 0.4, rot(10, 40, 30))
	end,
	Crane = function(k)
		k.b("D", 0, 0.7, 0, 3, 0.8, 3)
		k.b("P", 0, 2.7, 0.3, 0.8, 4, 0.8)
		k.b("S", 0, 2.2, 0.3, 1.1, 0.2, 1.1, rot(0, 45, 0))
		k.b("S", 0, 3.4, 0.3, 1.1, 0.2, 1.1, rot(0, 45, 0))
		k.b("G", 0, 1.9, -0.3, 0.9, 0.9, 0.5)
		k.b("S", 0, 4.9, -0.6, 0.6, 0.6, 4.2)
		k.b("D", 0, 4.7, 1.8, 1, 0.8, 1)
		k.c("D", 0, 3.9, -2.4, 0.1, 1.8)
		k.o("N", 0, 2.9, -2.4, 0.4)
	end,
	Forge = function(k)
		k.b("D", 0, 1.5, 0, 3.2, 2.4, 3)
		k.b("P", 0, 3, 0, 3.4, 0.6, 3.2)
		k.c("S", 1, 4.3, 0.6, 1, 2.2)
		k.b("N", 0, 1.6, -1.52, 1.6, 1, 0.1)
		k.b("S", 0, 0.7, -1.8, 1.2, 0.8, 0.8)
		k.b("D", 0, 1.1, -1.8, 0.8, 0.2, 0.5)
	end,
	Drone = function(k)
		k.c("P", 0, 2.6, 0, 1.6, 0.6)
		k.o("N", 0, 2.25, 0, 0.8)
		k.b("S", 0, 2.7, 0, 2.8, 0.2, 0.3, rot(0, 45, 0))
		k.b("S", 0, 2.7, 0, 2.8, 0.2, 0.3, rot(0, -45, 0))
		for _, x in { -1, 1 } do
			for _, z in { -1, 1 } do
				k.c("S", x, 2.8, z, 0.4, 0.4)
				k.c("G", x, 3.05, z, 1.3, 0.08)
				k.b("D", x * 0.7, 1.4, z * 0.7, 0.15, 1.4, 0.15)
			end
		end
	end,
	Box = function(k)
		k.b("P", 0, 1.8, 0, 3, 3, 3)
		for _, x in { -1.5, 1.5 } do
			for _, z in { -1.5, 1.5 } do
				k.b("S", x, 1.8, z, 0.35, 3.1, 0.35)
			end
		end
		for _, y in { 1.2, 1.8, 2.4 } do
			k.b("N", 0, y, -1.52, 2.2, 0.25, 0.1)
		end
		k.b("S", 0, 3.45, 0, 3.2, 0.3, 3.2)
		k.b("N", 0, 3.65, 0, 0.8, 0.1, 0.8)
	end,
	Spider = function(k)
		k.o("P", 0, 1.8, 0, 1.9)
		k.o("S", 0, 1.9, -1.1, 1.1)
		k.o("N", -0.25, 2.05, -1.6, 0.25)
		k.o("N", 0.25, 2.05, -1.6, 0.25)
		for side = 0, 1 do
			for _, angle in { -50, -17, 17, 50 } do
				local base = CFrame.new(0, 1.8, 0) * rot(0, angle + side * 180, 0)
				local seg1 = base * CFrame.new(0.75, 0.15, 0) * rot(0, 0, 20)
				local seg2 = base * CFrame.new(1.45, -0.55, 0) * rot(0, 0, -15)
				k.b("S", seg1.X, seg1.Y, seg1.Z, 1.6, 0.2, 0.2, seg1.Rotation)
				k.b("S", seg2.X, seg2.Y, seg2.Z, 0.2, 1.7, 0.2, seg2.Rotation)
			end
		end
	end,
	Gantry = function(k)
		k.b("S", -1.6, 2.5, 0, 0.6, 4.4, 0.6)
		k.b("S", 1.6, 2.5, 0, 0.6, 4.4, 0.6)
		k.b("D", -1.6, 0.45, 0, 1, 0.3, 1.4)
		k.b("D", 1.6, 0.45, 0, 1, 0.3, 1.4)
		k.b("P", 0, 4.8, 0, 4, 0.7, 1)
		k.b("N", 0.5, 4.3, 0, 0.8, 0.5, 0.8)
		k.c("D", 0.5, 3.3, 0, 0.1, 2)
		k.b("S", 0.5, 2.1, 0, 1, 0.8, 1)
	end,
	Tower = function(k)
		k.c("P", 0, 1.0, 0, 3, 1.4)
		k.c("P", 0, 2.4, 0, 2.2, 1.4)
		k.c("P", 0, 3.8, 0, 1.4, 1.4)
		k.c("S", 0, 1.7, 0, 3.15, 0.2)
		k.c("S", 0, 3.1, 0, 2.35, 0.2)
		k.c("N", 0, 2.0, 0, 2.3, 0.12)
		k.c("N", 0, 3.4, 0, 1.5, 0.12)
		k.c("S", 0, 5.2, 0, 0.15, 1.6)
		k.o("N", 0, 6.0, 0, 0.4)
	end,
	Orb = function(k)
		k.c("S", 0, 0.6, 0, 2.4, 0.6)
		k.o("G", 0, 2.5, 0, 3)
		k.o("N", 0, 2.5, 0, 1.4)
		k.c("S", 0, 2.5, 0, 3.4, 0.15)
	end,
	ScreenWall = function(k)
		k.b("S", 0, 0.9, 0.2, 0.6, 1.2, 0.8)
		k.b("D", 0, 2.9, 0, 4, 2.8, 0.4)
		k.b("N", 0, 2.9, -0.22, 3.6, 2.4, 0.1)
		for i, h in { 0.7, 1.2, 0.9, 1.6 } do
			k.b("P", -1.2 + (i - 1) * 0.8, 1.95 + h / 2, -0.29, 0.4, h, 0.05)
		end
	end,
	Roller = function(k)
		k.b("S", -1.7, 1, 0, 0.4, 1.6, 3.6)
		k.b("S", 1.7, 1, 0, 0.4, 1.6, 3.6)
		for _, z in { -1.1, 0, 1.1 } do
			k.c("P", 0, 1.4, z, 1, 3.4, "X")
		end
		k.c("N", -1.95, 1.4, 0, 0.5, 0.15, "X")
		k.b("D", 1.7, 2, 1.7, 0.4, 0.8, 0.4)
	end,
	Booth = function(k)
		k.b("P", 0, 1.9, 1.5, 3.2, 3.2, 0.2)
		k.b("P", -1.5, 1.9, 0, 0.2, 3.2, 3)
		k.b("P", 1.5, 1.9, 0, 0.2, 3.2, 3)
		k.b("G", 0, 2.1, 1.38, 2.2, 1.1, 0.1)
		k.b("P", 0, 0.8, -1.4, 3, 1, 0.6)
		k.b("S", 0, 3.6, 0, 3.6, 0.3, 3.6)
		k.b("N", 0, 3.0, -1.7, 2.4, 0.5, 0.1)
		k.b("S", 0, 0.45, 0, 3, 0.2, 3)
	end,
	Dummy = function(k)
		k.b("S", -0.4, 1.0, 0, 0.5, 1.4, 0.5)
		k.b("S", 0.4, 1.0, 0, 0.5, 1.4, 0.5)
		k.b("P", 0, 2.5, 0, 1.4, 1.6, 0.8)
		k.o("S", 0, 3.8, 0, 1)
		k.b("S", -1.0, 2.5, 0, 0.45, 1.5, 0.45)
		k.b("S", 1.0, 2.5, 0, 0.45, 1.5, 0.45)
		k.b("D", 0, 2.4, 1.6, 3, 3.6, 0.2)
		k.c("N", 0, 2.4, 1.46, 2.2, 0.1, "Z")
		k.c("P", 0, 2.4, 1.4, 1.4, 0.1, "Z")
		k.c("N", 0, 2.4, 1.34, 0.6, 0.1, "Z")
	end,
	Ring = function(k)
		for i = 0, 9 do
			local a = math.rad(i * 36)
			local role: Role = if i % 2 == 0 then "P" else "S"
			k.b(role, math.cos(a) * 1.5, 2.6 + math.sin(a) * 1.5, 0, 0.9, 0.55, 0.7, rot(0, 0, i * 36 + 90))
			if i % 2 == 1 then
				k.b("N", math.cos(a) * 1.5, 2.6 + math.sin(a) * 1.5, -0.38, 0.3, 0.3, 0.05)
			end
		end
		k.o("N", 0, 2.6, 0, 0.8)
		k.b("D", -1, 0.7, 0, 0.5, 0.8, 1.2)
		k.b("D", 1, 0.7, 0, 0.5, 0.8, 1.2)
	end,
	Turbine = function(k)
		k.b("D", 0, 0.9, 0, 1, 1.2, 1.2)
		k.c("P", 0, 2.4, 0, 3.2, 1.4, "Z")
		k.c("N", 0, 2.4, -0.8, 0.8, 0.3, "Z")
		k.c("G", 0, 2.4, -0.95, 3.4, 0.15, "Z")
		for i = 0, 5 do
			k.b("S", 0, 2.4, -0.82, 0.4, 1.4, 0.1, rot(0, 0, i * 60) * CFrame.new(0, 0.75, 0) * rot(25, 0, 0))
		end
	end,
	Tug = function(k)
		k.b("P", 0, 1.2, 0, 3, 1.2, 3.8)
		k.b("P", 0, 1.2, -2.3, 2, 1.2, 1)
		k.b("N", 0, 1.65, 0, 3.1, 0.2, 3.9)
		k.b("S", 0, 2.5, 0.5, 2, 1.2, 1.6)
		k.b("G", 0, 2.6, -0.32, 1.6, 0.5, 0.1)
		k.c("N", 0, 3.7, 0.9, 0.7, 1.2)
		k.c("S", 0, 3.5, 0.9, 0.8, 0.25)
		k.c("D", 0, 4.4, 0.3, 0.12, 1.4)
	end,
	Platform = function(k)
		for _, x in { -1.5, 1.5 } do
			for _, z in { -1.5, 1.5 } do
				k.c("D", x, 1.2, z, 0.5, 1.8)
				k.b("S", x, 3.0, z, 0.15, 0.9, 0.15)
			end
		end
		k.b("P", 0, 2.3, 0, 4, 0.4, 4)
		k.b("N", 0, 2.55, -1.95, 4, 0.1, 0.15)
		k.b("N", 0, 2.55, 1.95, 4, 0.1, 0.15)
		k.b("N", -1.95, 2.55, 0, 0.15, 0.1, 4)
		k.b("N", 1.95, 2.55, 0, 0.15, 0.1, 4)
		k.b("S", 1.4, 3.1, 1.4, 0.8, 1, 0.6)
		k.o("N", 1.4, 3.8, 1.4, 0.3)
	end,
	Satellite = function(k)
		k.c("D", 0, 1.0, 0, 0.5, 1.4)
		k.b("P", 0, 2.7, 0, 1.6, 1.6, 1.6)
		k.b("S", -1.7, 2.7, 0, 1.6, 0.08, 1)
		k.b("S", 1.7, 2.7, 0, 1.6, 0.08, 1)
		for _, x in { -2, -1.4, 1.4, 2 } do
			k.b("N", x, 2.76, 0, 0.06, 0.04, 1)
		end
		k.c("P", 0, 3.9, -0.4, 1.4, 0.15, "Z", rot(-30, 0, 0))
		k.o("N", 0, 4.1, -0.9, 0.3)
		k.c("S", 0.5, 3.9, 0.3, 0.1, 1)
	end,
	Tanks = function(k)
		for i, def in { { -1.2, 3.2 }, { 0, 2.6 }, { 1.2, 3.6 } } do
			local x, h = def[1], def[2]
			k.c("P", x, 0.3 + h / 2, 0.4, 1.1, h)
			k.o("S", x, 0.3 + h, 0.4, 1.1)
			k.c("S", x, 0.3 + h / 2, 0.4, 1.2, 0.2)
			if i == 2 then
				k.b("N", x, 1.8, -0.18, 0.4, 0.4, 0.05)
			end
		end
		k.c("S", 0, 0.7, -0.7, 0.25, 3, "X")
		k.c("N", 0.6, 1.2, -0.7, 0.5, 0.1, "Z")
	end,
	GlassCube = function(k)
		k.b("G", 0, 1.8, 0, 3, 3, 3)
		k.o("N", 0, 1.8, 0, 1.2)
		for _, x in { -1.5, 1.5 } do
			for _, z in { -1.5, 1.5 } do
				k.b("S", x, 1.8, z, 0.25, 3.1, 0.25)
			end
		end
		for _, y in { 0.35, 3.25 } do
			k.b("S", 0, y, -1.5, 3.1, 0.25, 0.25)
			k.b("S", 0, y, 1.5, 3.1, 0.25, 0.25)
			k.b("S", -1.5, y, 0, 0.25, 0.25, 3.1)
			k.b("S", 1.5, y, 0, 0.25, 0.25, 3.1)
		end
	end,
	DuckFactory = function(k)
		k.o("P", 0, 1.9, 0.2, 2.8)
		k.o("P", 0, 2.4, 1.6, 1)
		k.o("P", 0, 3.7, -0.9, 1.7)
		k.b("S", 0, 3.55, -1.95, 0.9, 0.25, 0.7)
		k.b("S", 0, 3.3, -1.9, 0.8, 0.2, 0.6)
		k.o("D", -0.5, 4.0, -1.6, 0.3)
		k.o("D", 0.5, 4.0, -1.6, 0.3)
		k.b("S", -1.4, 2.0, 0.4, 0.2, 1, 1.3)
		k.b("S", 1.4, 2.0, 0.4, 0.2, 1, 1.3)
		k.c("S", 0, 4.3, 1.0, 0.6, 1.6)
		k.c("N", 0, 5.15, 1.0, 0.7, 0.1)
	end,
	Printer = function(k)
		for _, x in { -1.6, 1.6 } do
			for _, z in { -1.4, 1.4 } do
				k.b("S", x, 2.1, z, 0.3, 3.6, 0.3)
			end
		end
		k.b("S", 0, 3.95, -1.4, 3.5, 0.25, 0.3)
		k.b("S", 0, 3.95, 1.4, 3.5, 0.25, 0.3)
		k.b("P", 0, 0.7, 0, 3, 0.2, 2.6)
		k.b("D", 0, 3.2, 0, 3.4, 0.25, 0.25)
		k.b("N", 0.6, 2.7, 0, 0.5, 0.5, 0.5)
		k.c("D", 0.6, 2.25, 0, 0.2, 0.35)
		k.b("P", -0.3, 1.25, 0, 1, 0.9, 1)
		k.c("S", 1.7, 4.3, 0, 0.9, 0.4, "X")
	end,
	Toaster = function(k)
		for _, x in { -1.4, 1.4 } do
			for _, z in { -0.8, 0.8 } do
				k.b("D", x, 0.45, z, 0.4, 0.3, 0.4)
			end
		end
		k.b("P", 0, 1.5, 0, 3.4, 2.2, 2.2)
		k.b("D", -0.7, 2.62, 0, 0.4, 0.1, 1.6)
		k.b("D", 0.7, 2.62, 0, 0.4, 0.1, 1.6)
		k.b("S", -0.7, 3.1, 0, 0.8, 1.2, 0.35)
		k.b("S", 0.7, 3.0, 0, 0.8, 1.2, 0.35)
		k.b("D", 1.8, 1.4, 0, 0.3, 0.3, 0.6)
		k.b("N", 0, 0.9, -1.12, 2.6, 0.2, 0.1)
		k.o("N", -1.0, 1.8, -1.12, 0.5)
		k.o("S", 1.0, 1.8, -1.12, 0.5)
	end,
	Chimney = function(k)
		k.b("S", 0, 0.8, 0, 2.4, 1, 2.4)
		k.c("P", 0, 2.1, 0, 1.9, 2.2)
		k.c("P", 0, 4.2, 0, 1.5, 2.2)
		k.c("S", 0, 1.7, 0, 1.95, 0.3)
		k.c("S", 0, 3.3, 0, 1.75, 0.3)
		k.c("D", 0, 5.4, 0, 1.7, 0.2)
		k.c("N", 0, 5.55, 0, 1.4, 0.08)
	end,
	Locomotive = function(k)
		k.c("P", 0, 1.9, -0.4, 1.8, 3, "Z")
		k.b("S", 0, 2.4, 1.3, 2, 2.4, 1.6)
		k.b("P", 0, 3.7, 1.3, 2.3, 0.25, 1.9)
		k.b("G", 0, 2.7, 0.49, 1.2, 0.8, 0.05)
		k.c("S", 0, 3.3, -1.4, 0.6, 1)
		k.c("N", 0, 3.85, -1.4, 0.7, 0.1)
		k.o("P", 0, 3.0, 0, 0.9)
		for _, z in { -1.2, 0, 1.2 } do
			k.c("D", -1.0, 0.7, z, 0.8, 0.3, "X")
			k.c("D", 1.0, 0.7, z, 0.8, 0.3, "X")
		end
		k.b("S", 0, 0.95, -1.95, 1.6, 0.2, 1.1, rot(-30, 0, 0))
		k.o("N", 0, 2.0, -1.95, 0.5)
		k.b("D", 0, 1.1, 0.3, 1.8, 0.4, 4)
	end,
}

local FALLBACK: (Kit) -> () = function(k)
	k.b("P", 0, 1.5, 0, 2.6, 2.4, 2.6)
	k.b("S", 0, 3.0, 0, 3, 0.5, 3)
	k.o("N", 0, 3.8, 0, 1)
end

--------------------------------------------------------------------------------
-- Machine builder
--------------------------------------------------------------------------------
local function makeKit(ctx: BuildKit.Context, def: Config.MachineDef, grade: number): Kit
	local v = def.Visual
	local m = Config.Visuals.Machine
	local primary, secondary = v.Primary, v.Secondary
	local neon = v.Neon or BuildKit.Lighten(secondary, 0.45)
	local pMat, sMat = Enum.Material.SmoothPlastic, Enum.Material.SmoothPlastic
	local pRefl, sRefl = 0, 0
	if grade == 1 then
		primary = primary:Lerp(m.ChromeColor, m.ChromeBlend)
		pMat, sMat = Enum.Material.Metal, Enum.Material.Metal
		pRefl = m.ChromeReflectance
	elseif grade >= 2 then
		primary = m.GoldColor
		secondary = BuildKit.Darken(m.GoldColor, 0.25)
		neon = m.GoldNeon
		pMat, sMat = Enum.Material.Metal, Enum.Material.Metal
		pRefl, sRefl = m.GoldReflectance, m.GoldReflectance
	end

	local function style(role: Role): BuildKit.PartProps
		if role == "P" then
			return { Color = primary, Material = pMat, Reflectance = pRefl }
		elseif role == "S" then
			return { Color = secondary, Material = sMat, Reflectance = sRefl }
		elseif role == "N" then
			return { Color = neon, Material = Enum.Material.Neon }
		elseif role == "G" then
			return { Color = m.GlassColor, Material = Enum.Material.Glass, Transparency = m.GlassTransparency }
		end
		return { Color = m.DarkColor, Material = Enum.Material.Metal }
	end

	local kit: Kit = {
		b = function(role, x, y, z, sx, sy, sz, r)
			return BuildKit.Box(ctx, at(x, y, z, r), Vector3.new(sx, sy, sz), primary, nil, style(role))
		end,
		c = function(role, x, y, z, d, len, axis, r)
			local size = if axis == "X"
				then Vector3.new(len, d, d)
				elseif axis == "Z" then Vector3.new(d, d, len)
				else Vector3.new(d, len, d)
			return BuildKit.Cyl(ctx, at(x, y, z, r), size, primary, nil, axis, style(role))
		end,
		o = function(role, x, y, z, d)
			return BuildKit.Sphere(ctx, Vector3.new(x, y, z), d, primary, nil, style(role))
		end,
		w = function(role, x, y, z, sx, sy, sz, r)
			return BuildKit.WedgeAt(ctx, at(x, y, z, r), Vector3.new(sx, sy, sz), primary, nil, style(role))
		end,
	}
	return kit
end

function MachineModelBuilder.Build(def: Config.MachineDef, grade: number): Model
	local override = BuildKit.OverrideFor({ def.Id, def.Visual.Shape })
	if override then
		override.Name = def.Id
		return override
	end

	local m = Config.Visuals.Machine
	local scale = m.Footprint / 4
	local model = BuildKit.Model(def.Id)
	model:SetAttribute("MachineId", def.Id)
	model:SetAttribute("Grade", grade)
	local ctx = BuildKit.NewContext(model, CFrame.identity, scale)

	local root = BuildKit.Box(ctx, Vector3.new(0, 0.15, 0), Vector3.new(4, 0.3, 4), def.Visual.Secondary, nil, {
		Name = "Root",
		Color = if grade >= 2 then BuildKit.Darken(m.GoldColor, 0.25) else def.Visual.Secondary,
		Material = if grade >= 1 then Enum.Material.Metal else Enum.Material.SmoothPlastic,
		CastShadow = false,
	})
	model.PrimaryPart = root
	root.PivotOffset = CFrame.new(0, -0.15 * scale, 0)

	local shape = SHAPES[def.Visual.Shape] or FALLBACK
	shape(makeKit(ctx, def, grade))

	local top = Instance.new("Attachment")
	top.Name = "FX"
	top.Position = Vector3.new(0, m.ParticleHeight * scale, 0)
	top.Parent = root
	if def.Visual.Particle then
		BuildKit.AddParticles(top, def.Visual.Particle)
	end
	if grade >= 2 then
		BuildKit.AddParticles(top, m.GradeParticle, m.GoldNeon)
	end
	local glow = m.RarityGlow[def.Rarity]
	if glow then
		BuildKit.Light(top, def.Visual.Neon or def.Visual.Secondary, glow, m.GlowRange)
	end
	return model
end

--------------------------------------------------------------------------------
-- Production stage builder
--------------------------------------------------------------------------------
local STAGE_NAMES = { "Feeder", "Processor", "Assembler", "Packer" }

-- Stage footprint is 9 (belt axis X) x 11 (Z); the belt itself is built by PlotService at y = BeltHeight.
function MachineModelBuilder.BuildStage(hallIndex: number, stageIndex: number, tierColor: Color3): Model
	local override =
		BuildKit.OverrideFor({ string.format("Stage_%d_%d", hallIndex, stageIndex), "Stage_" .. stageIndex })
	if override then
		override.Name = "Stage_" .. stageIndex
		return override
	end

	local hall = Config.Halls[hallIndex] or Config.Halls[1]
	local st = Config.Visuals.Stage
	local H, A, T = hall.Color, hall.AccentColor, tierColor
	local M, Dk = st.MetalColor, st.DarkColor
	local model = BuildKit.Model("Stage_" .. stageIndex)
	model:SetAttribute("StageName", STAGE_NAMES[stageIndex] or "Stage")
	local ctx = BuildKit.NewContext(model, CFrame.identity, st.Scale)
	local metal = Enum.Material.Metal
	local plastic = Enum.Material.SmoothPlastic
	local stripeH = st.TierStripeHeight
	local tierAttr = { Attributes = { TierPart = true } } :: BuildKit.PartProps

	local function box(
		x: number,
		y: number,
		z: number,
		sx: number,
		sy: number,
		sz: number,
		color: Color3,
		mat: Enum.Material?,
		r: CFrame?
	)
		return BuildKit.Box(ctx, at(x, y, z, r), Vector3.new(sx, sy, sz), color, mat or plastic)
	end
	local function cyl(
		x: number,
		y: number,
		z: number,
		d: number,
		len: number,
		color: Color3,
		axis: string?,
		mat: Enum.Material?,
		r: CFrame?
	)
		local size = if axis == "X"
			then Vector3.new(len, d, d)
			elseif axis == "Z" then Vector3.new(d, d, len)
			else Vector3.new(d, len, d)
		return BuildKit.Cyl(ctx, at(x, y, z, r), size, color, mat or plastic, axis)
	end
	local function ball(x: number, y: number, z: number, d: number, color: Color3, mat: Enum.Material?)
		return BuildKit.Sphere(ctx, Vector3.new(x, y, z), d, color, mat or plastic)
	end
	local function tier(x: number, y: number, z: number, sx: number, sz: number)
		return BuildKit.Box(ctx, Vector3.new(x, y, z), Vector3.new(sx, stripeH, sz), T, Enum.Material.Neon, tierAttr)
	end

	local root = BuildKit.Box(ctx, Vector3.new(0, 0.2, 0), Vector3.new(9, 0.4, 11), Dk, metal, {
		Name = "Root",
		CastShadow = false,
	})
	model.PrimaryPart = root
	root.PivotOffset = CFrame.new(0, -0.2 * st.Scale, 0)

	if stageIndex == 1 then
		-- Feeder: raw-material hopper on legs with a chute dropping onto the belt.
		for _, x in { -2.2, 2.2 } do
			for _, z in { -2.6, 2.6 } do
				box(x, 2.15, z, 0.5, 3.5, 0.5, M, metal)
			end
		end
		box(0, 3.6, 0, 2.8, 0.9, 2.8, H)
		box(0, 4.5, 0, 4.2, 1, 4.2, H)
		box(0, 5.5, 0, 5.6, 1.2, 5.6, H)
		tier(0, 6.35, 0, 5.8, 5.8)
		ball(-1.2, 6.5, -0.8, 1.6, A)
		ball(1.1, 6.6, 0.9, 1.5, A)
		ball(0.2, 6.9, -0.2, 1.4, A)
		cyl(0, 2.5, 0, 0.9, 1.6, A)
		box(3.2, 1.0, -3.4, 1.6, 1.2, 1.6, Dk, metal)
		ball(3.2, 1.9, -3.4, 0.5, T, Enum.Material.Neon)
	elseif stageIndex == 2 then
		-- Processor: two side blocks and a bridge, gear on the front face, pistons on top.
		for _, z in { -3.2, 3.2 } do
			box(0, 2.1, z, 6, 3.4, 2.4, H)
			box(0, 0.9, z + (if z < 0 then -1.3 else 1.3), 4, 0.5, 0.2, Dk, metal)
		end
		box(0, 4.7, 0, 6, 1.2, 8.8, H)
		tier(0, 5.55, 0, 6.2, 9)
		cyl(0, 2.4, -4.5, 3, 0.4, M, "Z", metal)
		for i = 0, 7 do
			box(0, 2.4, -4.5, 0.5, 0.7, 0.4, M, metal, rot(0, 0, i * 45) * CFrame.new(0, 1.65, 0))
		end
		ball(0, 2.4, -4.8, 0.8, T, Enum.Material.Neon)
		for _, x in { -1.5, 1.5 } do
			cyl(x, 6.6, 0, 0.9, 2.2, A, nil, metal)
			box(x, 5.6, 0, 1.4, 0.3, 1.4, Dk, metal)
		end
		cyl(2.2, 6.8, 2.4, 0.9, 2, Dk, nil, metal)
		ball(-2.4, 5.8, 3.4, 0.6, T, Enum.Material.Neon)
	elseif stageIndex == 3 then
		-- Assembler: portal arch over the belt with a hanging welding arm.
		for _, z in { -3.8, 3.8 } do
			box(0, 3.5, z, 1.2, 6.5, 1.2, M, metal)
			box(0, 0.5, z, 2.4, 0.6, 2.2, Dk, metal)
		end
		box(0, 7.0, 0, 2.2, 1.2, 9.6, H)
		tier(0, 7.85, 0, 2.4, 9.8)
		cyl(0, 6.2, 0, 1.4, 0.6, Dk, nil, metal)
		box(0, 5.1, -0.3, 0.7, 2.2, 0.7, A, nil, rot(-12, 0, 0))
		ball(0, 4.0, -0.6, 0.8, M, metal)
		box(0, 3.1, -0.9, 0.5, 1.9, 0.5, H, nil, rot(-12, 0, 0))
		local tip = ball(0, 2.2, -1.1, 0.7, T, Enum.Material.Neon)
		BuildKit.AddParticles(tip, "Sparks", nil, Enum.NormalId.Bottom, 0.5)
		box(0, 3.2, 3.0, 1.6, 1.2, 0.2, Dk, metal)
		ball(0, 3.2, 2.88, 0.4, T, Enum.Material.Neon)
	else
		-- Packer: boxed housing with a laser sealer across the belt and a stack of finished crates.
		for _, z in { -3.2, 3.2 } do
			box(0, 1.9, z, 5.5, 3.2, 2.4, H)
		end
		box(0, 4.4, 0, 6, 0.8, 8.8, H)
		tier(0, 4.95, 0, 6.2, 9)
		box(0, 3.3, 0, 0.3, 0.3, 6.4, T, Enum.Material.Neon)
		box(0, 3.9, 0, 2.6, 0.25, 1.8, A, nil, rot(0, 0, 12))
		for _, def in { { -1.5, 1.1, 5.0 }, { 1.5, 1.1, 5.0 }, { 0, 2.8, 5.0 } } do
			box(def[1], def[2], def[3], 1.6, 1.6, 1.6, A)
			box(def[1], def[2], def[3], 0.3, 1.65, 1.65, T, Enum.Material.Neon)
		end
		cyl(-2.6, 5.4, 3.2, 0.7, 1.6, Dk, nil, metal)
		ball(-2.6, 6.4, 3.2, 0.5, T, Enum.Material.Neon)
	end
	return model
end

return MachineModelBuilder
