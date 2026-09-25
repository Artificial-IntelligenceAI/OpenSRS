--!strict
-- SPDX-License-Identifier: Apache-2.0

local Characters = require(script.Parent.Characters)
local Remotes = require(script.Parent.Remotes)

local Main = {}

-- `replicated` is the folder clients will see.
function Main.start(replicated: Folder)
	Characters.start(Remotes.create(replicated))
end

return table.freeze(Main)
