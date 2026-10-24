local Clipboard = {}

local setter = setclipboard or toclipboard

function Clipboard.isSupported()
	return setter ~= nil
end

function Clipboard.copy(text)
	if not setter then
		return false
	end
	
	return (pcall(setter, text))
end

return Clipboard
