--!strict
-- SPDX-License-Identifier: Apache-2.0

-- Installs OpenSRS. Drop the OpenSRS folder into ServerScriptService and this
-- script does the rest: server code stays here, where clients can't see it,
-- and a copy of the shared and client code goes to ReplicatedStorage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local root = script.Parent
assert(root.Parent == ServerScriptService, "OpenSRS must be placed directly in ServerScriptService.")
assert(
	ReplicatedStorage:FindFirstChild("OpenSRS") == nil,
	"ReplicatedStorage already has something named OpenSRS. Remove it and try again."
)

-- Settings first: everything else reads them when it loads.
local Settings = require(root.Shared.Settings)
local settingsFolder = root:FindFirstChild("Settings")
local overridesModule = settingsFolder and settingsFolder:FindFirstChild("Overrides")
local overrides = if overridesModule and overridesModule:IsA("ModuleScript")
	then (require :: any)(overridesModule)
	else nil
local settings = Settings.resolve(settingsFolder, overrides)
Settings.apply(settings)

local replicated = Instance.new("Folder")
replicated.Name = "OpenSRS"
root.Shared:Clone().Parent = replicated
local assets = root:FindFirstChild("Assets") -- only in the "with models" download
if assets then
	assets:Clone().Parent = replicated
end
-- Clients predict with exactly the values the server settled on.
Settings.write(settings, replicated)
require(root.Server.Main).start(replicated)
root.Client:Clone().Parent = replicated
replicated.Parent = ReplicatedStorage

-- Set last, so clients know everything above has arrived once they see it.
replicated:SetAttribute("Ready", true)
