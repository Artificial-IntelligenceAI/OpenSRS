--!strict
-- SPDX-License-Identifier: Apache-2.0

local Protocol = require(script.Parent.Parent.Shared.Protocol)

export type Remotes = {
	input: UnreliableRemoteEvent,
	state: UnreliableRemoteEvent,
	snapshot: UnreliableRemoteEvent,
}

local Remotes = {}

function Remotes.create(parent: Instance): Remotes
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"

	local function make(name: string): UnreliableRemoteEvent
		local remote = Instance.new("UnreliableRemoteEvent")
		remote.Name = name
		remote.Parent = folder
		return remote
	end

	local remotes = {
		input = make(Protocol.Remotes.Input),
		state = make(Protocol.Remotes.State),
		snapshot = make(Protocol.Remotes.Snapshot),
	}
	folder.Parent = parent
	return remotes
end

return table.freeze(Remotes)
