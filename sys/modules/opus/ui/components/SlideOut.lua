local class = require('opus.class')
local UI    = require('opus.ui')

UI.SlideOut = class(UI.Window)
UI.SlideOut.defaults = {
	UIElement = 'SlideOut',
	pageType = 'modal',
}
function UI.SlideOut:layout()
	UI.Window.layout(self)
	if not self.canvas or not self.canvas.layers then
		self.canvas = self:addLayer()
	else
		self.canvas:resize(self.width, self.height)
	end
end

function UI.SlideOut:enable()
end

function UI.SlideOut:toggle()
	if self.enabled then
		self:hide()
	else
		self:show()
	end
end

function UI.SlideOut:show(...)
	self:addTransition('expandUp')
	self.canvas:raise()
	self.canvas:setVisible(true)
	UI.Window.enable(self, ...)
	self:draw()
	self:capture(self)
	self:focusFirst()
end

function UI.SlideOut:disable()
	self.canvas:setVisible(false)
	UI.Window.disable(self)
end

function UI.SlideOut:hide()
	self:disable()
	self:release(self)
	self:refocus()
end

function UI.SlideOut:eventHandler(event)
	if event.type == 'slide_show' then
		self:show()
		return true

	elseif event.type == 'slide_hide' then
		self:hide()
		return true
	end
end

function UI.SlideOut.example()
	-- for the transistion to work properly, the parent must have a canvas
	return UI.ActiveLayer {
		--y = 2,
		button = UI.Button {
			x = 2, y = 5,
			text = 'show',
		},
		slideOut = UI.SlideOut {
			backgroundColor = _G.colors.yellow,
			y = -4, height = 4, x = 5, ex = -5,
			titleBar = UI.TitleBar { title = 'example', expand = 'height', event='slide_hide' },
			grid = UI.ScrollingGrid {
				x = 2, ex = -2, y = 3, ey = -2,
				text = 'hide',
				columns = {
					{ heading = 'test', key = 'abc' }
				},
				values = {
					{ abc = '1234556' },
					{ abc = 'asdfsfd' },
					{ abc = '12fasfdsdf34556' },
					{ abc = 'sdf vss fd' },
				}
			},
		},
		eventHandler = function (self, event)
			if event.type == 'button_press' then
				self.slideOut.canvas.xxx = true
				self.slideOut:toggle()
			end
		end,
	}
end
