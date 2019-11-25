local class = require('opus.class')
local UI    = require('opus.ui')

local colors = _G.colors
local _rep   = string.rep
local _sub   = string.sub

-- For manipulating text in a fixed width string
local SB = class()
function SB:init(width)
	self.width = width
	self.buf = _rep(' ', width)
end
function SB:insert(x, str, width)
	if x < 1 then
		x = self.width + x + 1
	end
	width = width or #str
	if x + width - 1 > self.width then
		width = self.width - x
	end
	if width > 0 then
		self.buf = _sub(self.buf, 1, x - 1) .. _sub(str, 1, width) .. _sub(self.buf, x + width)
	end
end
function SB:fill(x, ch, width)
	width = width or self.width - x + 1
	self:insert(x, _rep(ch, width))
end
function SB:center(str)
	self:insert(math.max(1, math.ceil((self.width - #str + 1) / 2)), str)
end
function SB:get()
	return self.buf
end

UI.TitleBar = class(UI.Window)
UI.TitleBar.defaults = {
	UIElement = 'TitleBar',
	height = 1,
	textColor = colors.white,
	backgroundColor = colors.cyan,
	title = '',
	frameChar = UI.extChars and '\140' or '-',
	closeInd = UI.extChars and '\215' or '*',
}
function UI.TitleBar:draw()
	local sb = SB(self.width)
	sb:fill(2, self.frameChar, sb.width - 3)
	sb:center(string.format(' %s ', self.title))
	if self.previousPage or self.event then
		sb:insert(-1, self.closeInd)
	else
		sb:insert(-2, self.frameChar)
	end
	self:write(1, 1, sb:get())
end

function UI.TitleBar:eventHandler(event)
	if event.type == 'mouse_click' then
		if (self.previousPage or self.event) and event.x == self.width then
			if self.event then
				self:emit({ type = self.event, element = self })
			elseif type(self.previousPage) == 'string' or
				 type(self.previousPage) == 'table' then
				UI:setPage(self.previousPage)
			else
				UI:setPreviousPage()
			end
			return true
		end

	elseif event.type == 'mouse_down' then
		self.anchor = { x = event.x, y = event.y, ox = self.parent.x, oy = self.parent.y, h = self.parent.height }

	elseif event.type == 'mouse_drag' then
		if self.expand == 'height' then
			local d = event.y
			if self.anchor.h - d > 0 and self.anchor.oy + d > 0 then
				self.parent:reposition(self.parent.x, self.anchor.oy + event.y, self.width, self.anchor.h - d)
				self.parent.parent:draw()
			end

		elseif self.moveable then
			local d = event.y
			if self.anchor.oy + d > 0 and self.anchor.oy + d <= self.parent.parent.height then
				self.parent:move(self.anchor.ox + event.x, self.anchor.oy + event.y)
				self.parent.parent:draw()
			end
		end
	end
end

function UI.TitleBar.example()
	return UI.Window {
		win1 = UI.Window {
			x = 9, y = 2, ex = -9, ey = -3,
			backgroundColor = colors.green,
			titleBar = UI.TitleBar {
				title = 'test',  moveable = true,
			},
			focus = function (self)
				self:raise()
			end,
		},
		win2 = UI.Window {
			x = 7, y = 2, ex = -7, ey = -2,
			backgroundColor = colors.orange,
			titleBar = UI.TitleBar {
				title = 'test', moveable = true,
			},
			focus = function (self)
				self:raise()
			end,
		},
		draw = function(self)
			for i = 1, self.height do
				self:write(1, i, self.bg or '')
			end
			for _,v in pairs(self.children) do
				v:draw()
			end
		end,
		enable = function (self)
			require('opus.event').onInterval(15, function()
				self.bg = string.rep(string.char(math.random(33, 126)), self.width)
				self:draw()
				self:sync()
			end)
			UI.Window.enable(self)
		end
	}
end
