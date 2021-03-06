local UI    = require('opus.ui')
local Util  = require('opus.util')

local colors = _G.colors
local help   = _G.help

UI:configure('Help', ...)

local topics = { }
for _,topic in pairs(help.topics()) do
	table.insert(topics, { name = topic, lname = topic:lower() })
end

UI:addPage('main', UI.Page {
	labelText = UI.Text {
		x = 3, y = 2,
		value = 'Search',
	},
	filter = UI.TextEntry {
		x = 10, y = 2, ex = -3,
		limit = 32,
	},
	grid = UI.ScrollingGrid {
		y = 4,
		values = topics,
		columns = {
			{ heading = 'Topic', key = 'name' },
		},
		sortColumn = 'lname',
	},
	accelerators = {
		[ 'control-q' ] = 'quit',
		enter = 'grid_select',
	},
	eventHandler = function(self, event)
		if event.type == 'quit' then
			UI:quit()

		elseif event.type == 'grid_select' then
			if self.grid:getSelected() then
				local name = self.grid:getSelected().name

				UI:setPage('topic', name)
			end

		elseif event.type == 'text_change' then
			if not event.text then
				self.grid.values = topics
			else
				self.grid.values = { }
				for _,f in pairs(topics) do
					if string.find(f.lname, event.text:lower()) then
						table.insert(self.grid.values, f)
					end
				end
			end
			self.grid:update()
			self.grid:setIndex(1)
			self.grid:draw()
		else
			return UI.Page.eventHandler(self, event)
		end
	end,
})

UI:addPage('topic', UI.Page {
	backgroundColor = colors.black,
	titleBar = UI.TitleBar {
		title = 'text',
		event = 'back',
	},
	helpText = UI.TextArea {
		backgroundColor = colors.black,
		x = 2, ex = -1, y = 3, ey = -2,
	},
	accelerators = {
		[ 'control-q' ] = 'back',
		backspace = 'back',
	},
	enable = function(self, name)
		local f = help.lookup(name)

		self.titleBar.title = name
		self.helpText:setText(f and Util.readFile(f) or 'No help available for ' .. name)

		return UI.Page.enable(self)
	end,
	eventHandler = function(self, event)
		if event.type == 'back' then
			UI:setPage('main')
		end
		return UI.Page.eventHandler(self, event)
	end,
})

local args = Util.parse(...)
UI:setPage(args[1] and 'topic' or 'main', args[1])
UI:start()
