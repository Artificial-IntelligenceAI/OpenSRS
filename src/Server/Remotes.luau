--!strict
-- SPDX-License-Identifier: Apache-2.0

local Protocol = require(script.Parent.Parent.Shared.Protocol)

export type Remotes = {
	input: UnreliableRemoteEvent,
	state: UnreliableRemoteEvent,
	snapshot: UnreliableRemoteEvent,
	shotResult: RemoteEvent,
	shots: UnreliableRemoteEvent,
	life: RemoteEvent,
}

local Remotes = {}

function Remotes.create(parent: Instance): Remotes
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"

	local function unreliable(name: string): UnreliableRemoteEvent
		local remote = Instance.new("UnreliableRemoteEvent")
		remote.Name = name
		remote.Parent = folder
		return remote
	end

	local function reliable(name: string): RemoteEvent
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		return remote
	end

	local remotes = {
		input = unreliable(Protocol.Remotes.Input),
		state = unreliable(Protocol.Remotes.State),
		snapshot = unreliable(Protocol.Remotes.Snapshot),
		shotResult = reliable(Protocol.Remotes.ShotResult),
		shots = unreliable(Protocol.Remotes.Shots),
		life = reliable(Protocol.Remotes.Life),
	}
	folder.Parent = parent
	return remotes
end

return table.freeze(Remotes)
