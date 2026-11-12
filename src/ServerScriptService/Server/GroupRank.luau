--!strict
--[[
	GroupRank: a player's rank in a group via GroupService:GetGroupsAsync
	(Player:GetRankInGroupAsync is deprecated). Returns (ok, rank); rank 0 = not a member.
]]

local GroupService = game:GetService("GroupService")

local Retry = require(script.Parent.Retry)

local GroupRank = {}

function GroupRank.GetAsync(userId: number, groupId: number): (boolean, number)
	local ok, groups = Retry.Call("GetGroupsAsync", function(): { any }
		return GroupService:GetGroupsAsync(userId)
	end)
	if not ok or type(groups) ~= "table" then
		return false, 0
	end
	for _, group in groups :: { any } do
		if type(group) == "table" and group.Id == groupId then
			return true, if type(group.Rank) == "number" then group.Rank else 0
		end
	end
	return true, 0
end

return GroupRank
