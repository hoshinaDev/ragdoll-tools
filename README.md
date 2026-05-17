# Server Ragdoll Module for Roblox

ModuleScript server-side para ragdoll em personagens **R6** e **R15**, feito para encaixar rapido em projetos **Rojo**.

## Instalacao rapida

1. Copie `src/ServerScriptService/Ragdoll` para o `ServerScriptService` do seu projeto Rojo.
2. Faca require no servidor:

```lua
local ServerScriptService = game:GetService("ServerScriptService")
local Ragdoll = require(ServerScriptService.Ragdoll)
```

3. Use em qualquer character:

```lua
Ragdoll.Ragdoll(character, { Duration = 3 })
```

## API

```lua
Ragdoll.Ragdoll(character, options?)      -- ativa ragdoll
Ragdoll.Unragdoll(character)             -- restaura o character
Ragdoll.Toggle(character, state?, options?)
Ragdoll.IsRagdolled(character)
Ragdoll.BindDeath(character, options?)   -- deixa morrer em ragdoll sem quebrar joints
Ragdoll.Cleanup(character)
```

## Options

```lua
{
	Duration = 3,              -- opcional: restaura automaticamente depois de N segundos
	CollideLimbs = true,       -- partes do corpo colidem durante o ragdoll
	KeepRootCollidable = false,
	DisableGettingUp = true,
	BreakJointsOnDeath = false
}
```

## Exemplo server-side

```lua
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Ragdoll = require(ServerScriptService.Ragdoll)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		Ragdoll.BindDeath(character)

		-- Exemplo: ragdoll temporario
		task.delay(5, function()
			if character.Parent then
				Ragdoll.Ragdoll(character, { Duration = 2 })
			end
		end)
	end)
end)
```

## Observacoes

- Tudo roda no servidor.
- O modulo nao usa RemoteEvent.
- O modulo nao destroi os `Motor6D`; ele desativa temporariamente os joints do corpo e cria `BallSocketConstraint`.
- Em morte, use `BindDeath` para definir `Humanoid.BreakJointsOnDeath = false` e permitir o ragdoll.
- Para integrar em outro Rojo, basta apontar o `$path` para `src/ServerScriptService/Ragdoll`.
