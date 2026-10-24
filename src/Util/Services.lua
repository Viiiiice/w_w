local Services = {}

local cloneref = cloneref or function(x)
	return x
end

return setmetatable(Services, {
	__index = function(self, name)
		local service = cloneref(game:GetService(name))
		rawset(self, name, service)
		return service
	end,
})
