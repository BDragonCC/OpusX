local Event = require('opus.event')
local UI    = require('opus.ui')

local kernel     = _G.kernel
local multishell = _ENV.multishell

UI:configure('Tasks', ...)

local page = UI.Page {
	menuBar = UI.MenuBar {
		buttons = {
			{ text = 'Activate',  event = 'activate'  },
			{ text = 'Terminate', event = 'terminate' },
		},
	},
	grid = UI.ScrollingGrid {
		y = 2,
		columns = {
			{ heading = 'ID',     key = 'uid',      width = 3 },
			{ heading = 'Title',  key = 'title'     },
			{ heading = 'Status', key = 'status'    },
			{ heading = 'Time',   key = 'timestamp' },
		},
		values = kernel.routines,
		sortColumn = 'uid',
		autospace = true,
		getDisplayValues = function (_, row)
			local elapsed = os.clock()-row.timestamp
			return {
				uid = row.uid,
				title = row.title,
				status = row.isDead and 'error' or coroutine.status(row.co),
				timestamp = elapsed < 60 and
					string.format("%ds", math.floor(elapsed)) or
					string.format("%sm", math.floor(elapsed/6)/10),
			}
		end
	},
	accelerators = {
		[ 'control-q' ] = 'quit',
		space = 'activate',
		t = 'terminate',
	},
	eventHandler = function (self, event)
		local t = self.grid:getSelected()
		if t then
			if event.type == 'activate' or event.type == 'grid_select' then
				multishell.setFocus(t.uid)
			elseif event.type == 'terminate' then
				multishell.terminate(t.uid)
			end
		end
		if event.type == 'quit' then
			Event.exitPullEvents()
		end
		UI.Page.eventHandler(self, event)
	end
}

Event.onInterval(1, function()
	page.grid:update()
	page.grid:draw()
	page:sync()
end)

UI:setPage(page)
UI:pullEvents()
