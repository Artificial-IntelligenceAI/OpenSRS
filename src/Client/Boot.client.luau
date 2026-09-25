--!strict
-- SPDX-License-Identifier: Apache-2.0

local root = script.Parent.Parent
if not root:GetAttribute("Ready") then
	root:GetAttributeChangedSignal("Ready"):Wait()
end

-- Use the exact settings the server published, before anything reads them.
local Settings = require(root.Shared.Settings)
Settings.apply(Settings.resolve(root:WaitForChild("Settings"), nil))

require(script.Parent.Controller).start()
