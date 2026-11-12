--!strict
-- NumberFormat: compact, readable numbers and durations for the UI.

local NumberFormat = {}

local SUFFIXES = {
	"",
	"K",
	"M",
	"B",
	"T",
	"Qa",
	"Qi",
	"Sx",
	"Sp",
	"Oc",
	"No",
	"Dc",
	"Ud",
	"Dd",
	"Td",
	"Qad",
	"Qid",
	"Sxd",
	"Spd",
	"Ocd",
	"Nod",
	"Vg",
	"Uvg",
	"Dvg",
	"Tvg",
	"Qavg",
	"Qivg",
	"Sxvg",
	"Spvg",
	"Ocvg",
	"Novg",
	"Tg",
}

-- 1234 -> "1.23K", 5e40 -> "50Tvg"; beyond the suffix table falls back to "1.23e99".
function NumberFormat.Short(n: number): string
	if n ~= n then
		return "0"
	end
	local sign = if n < 0 then "-" else ""
	local x = math.abs(n)
	if x < 1000 then
		if x == math.floor(x) then
			return sign .. string.format("%d", x)
		end
		return sign .. string.format("%.1f", x)
	end
	local tier = math.floor(math.log10(x) / 3)
	if tier >= #SUFFIXES then
		return sign .. string.format("%.2fe%d", x / 10 ^ math.floor(math.log10(x)), math.floor(math.log10(x)))
	end
	local scaled = x / 10 ^ (tier * 3)
	local text
	if scaled >= 100 then
		text = string.format("%d", math.floor(scaled))
	elseif scaled >= 10 then
		text = string.format("%.1f", math.floor(scaled * 10) / 10)
	else
		text = string.format("%.2f", math.floor(scaled * 100) / 100)
	end
	return sign .. text .. SUFFIXES[tier + 1]
end

function NumberFormat.Cash(n: number): string
	return "$" .. NumberFormat.Short(n)
end

-- 3725 -> "1h 02m", 125 -> "2m 05s", 9 -> "9s"
function NumberFormat.Duration(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local d = math.floor(s / 86400)
	local h = math.floor((s % 86400) / 3600)
	local m = math.floor((s % 3600) / 60)
	local sec = s % 60
	if d > 0 then
		return string.format("%dd %02dh", d, h)
	elseif h > 0 then
		return string.format("%dh %02dm", h, m)
	elseif m > 0 then
		return string.format("%dm %02ds", m, sec)
	end
	return string.format("%ds", sec)
end

-- 0.255 -> "25.5%"
function NumberFormat.Percent(fraction: number): string
	local p = fraction * 100
	if p == math.floor(p) then
		return string.format("%d%%", p)
	end
	return string.format("%.1f%%", p)
end

-- Comma-grouped integer for small numbers (e.g. "1,200 Credits").
function NumberFormat.Commas(n: number): string
	local s = string.format("%d", math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return (formatted:gsub("^%-,", "-"))
end

return NumberFormat
