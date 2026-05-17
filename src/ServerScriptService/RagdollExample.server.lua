-- Optional example. Keep or delete this file in your Rojo project.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Ragdoll = require(ServerScriptService.Ragdoll)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		Ragdoll.BindDeath(character)

		-- Quick smoke test:
		-- task.wait(3)
		-- Ragdoll.Ragdoll(character, { Duration = 2 })
	end)
end)
