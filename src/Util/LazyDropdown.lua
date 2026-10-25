local LazyDropdown = {}

function LazyDropdown.wrap(dropdown, getValues)
	local self = { dirty = true, last = nil }

	local function same(a, b)
		if not a or #a ~= #b then
			return false
		end
		for i, v in ipairs(a) do
			if b[i] ~= v then
				return false
			end
		end
		return true
	end

	function self.rebuild()
		self.dirty = false
		local values = getValues()
		if not same(self.last, values) then
			self.last = values
			dropdown:SetValues(values)
		end
	end

	function self.markDirty()
		self.dirty = true
	end

	local open = dropdown.OpenDropdown
	dropdown.OpenDropdown = function(...)
		if self.dirty then
			pcall(self.rebuild)
		end
		return open(...)
	end

	return self
end

return LazyDropdown
