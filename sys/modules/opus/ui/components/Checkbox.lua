local class = require('opus.class')
local UI    = require('opus.ui')

local colors = _G.colors

UI.Checkbox = class(UI.Window)
UI.Checkbox.defaults = {
	UIElement = 'Checkbox',
	nochoice = 'Select',
	checkedIndicator = UI.extChars and '\4' or 'X',
	leftMarker = UI.extChars and '\124' or '[',
	rightMarker = UI.extChars and '\124' or ']',
	value = false,
	textColor = colors.white,
	backgroundColor = colors.black,
	backgroundFocusColor = colors.lightGray,
	height = 1,
	width = 3,
	accelerators = {
		space = 'checkbox_toggle',
		mouse_click = 'checkbox_toggle',
	}
}
UI.Checkbox.inherits = {
	labelBackgroundColor = 'backgroundColor',
}
function UI.Checkbox:postInit()
	self.width = self.label and #self.label + 4 or 3
end

function UI.Checkbox:draw()
	local bg = self.focused and self.backgroundFocusColor or self.backgroundColor
	local x = 1
	if self.label then
		self:write(1, 1, self.label, self.labelBackgroundColor)
		x = #self.label + 2
	end
	self:write(x,     1, self.leftMarker, self.backgroundColor, self.textColor)
	self:write(x + 1, 1, not self.value and ' ' or self.checkedIndicator, bg)
	self:write(x + 2, 1, self.rightMarker, self.backgroundColor, self.textColor)
end

function UI.Checkbox:focus()
	self:draw()
end

function UI.Checkbox:setValue(v)
	self.value = not not v
end

function UI.Checkbox:reset()
	self.value = false
	self:draw()
end

function UI.Checkbox:eventHandler(event)
	if event.type == 'checkbox_toggle' then
		self.value = not self.value
		self:emit({ type = 'checkbox_change', checked = self.value, element = self })
		self:draw()
		return true
	end
end

function UI.Checkbox.example()
	return UI.Window {
		ex1 = UI.Checkbox {
			label = 'test',
			x = 2, y = 2,
		},
		ex2 = UI.Checkbox {
			x = 2, y = 4,
		},
	}
end
