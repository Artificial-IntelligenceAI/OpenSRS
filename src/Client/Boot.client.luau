--!strict
-- SPDX-License-Identifier: Apache-2.0

local root = script.Parent.Parent
if not root:GetAttribute("Ready") then
	root:GetAttributeChangedSignal("Ready"):Wait()
end

require(script.Parent.Controller).start()
