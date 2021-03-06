local class = require('opus.class')
local UI    = require('opus.ui')
local Util  = require('opus.util')

local colors = _G.colors

UI.Button = class(UI.Window)
UI.Button.defaults = {
	UIElement = 'Button',
	text = 'button',
	backgroundColor = colors.lightGray,
	backgroundFocusColor = colors.gray,
	textFocusColor = colors.white,
	textInactiveColor = colors.gray,
	textColor = colors.black,
	centered = true,
	height = 1,
	focusIndicator = ' ',
	event = 'button_press',
	accelerators = {
		space = 'button_activate',
		enter = 'button_activate',
		mouse_click = 'button_activate',
	}
}
function UI.Button:setParent()
	if not self.width and not self.ex then
		self.width = #self.text + 2
	end
	UI.Window.setParent(self)
end

function UI.Button:draw()
	local fg = self.textColor
	local bg = self.backgroundColor
	local ind = ' '
	if self.focused then
		bg = self.backgroundFocusColor
		fg = self.textFocusColor
		ind = self.focusIndicator
	elseif self.inactive then
		fg = self.textInactiveColor
	end
	local text = ind .. self.text .. ' '
	if self.centered then
		self:clear(bg)
		self:centeredWrite(1 + math.floor(self.height / 2), text, bg, fg)
	else
		self:write(1, 1, Util.widthify(text, self.width), bg, fg)
	end
end

function UI.Button:focus()
	if self.focused then
		self:scrollIntoView()
	end
	self:draw()
end

function UI.Button:eventHandler(event)
	if event.type == 'button_activate' then
		self:emit({ type = self.event, button = self })
		return true
	end
	return false
end

function UI.Button.example()
	return UI.Window {
		button1 = UI.Button {
			x = 2, y = 2,
			text = 'Press',
		},
		button2 = UI.Button {
			x = 2, y = 4,
			backgroundColor = colors.green,
			event = 'custom_event',
		},
		button3 = UI.Button {
			x = 12, y = 2,
			height = 5,
			event = 'big_event',
			text = 'large button'
		}
	}
end
