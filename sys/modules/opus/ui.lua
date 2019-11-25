local class      = require('opus.class')
local Event      = require('opus.event')
local Input      = require('opus.input')
local Transition = require('opus.ui.transition')
local Util       = require('opus.util')

local _rep       = string.rep
local _sub       = string.sub
local colors     = _G.colors
local device     = _G.device
local fs         = _G.fs
local os         = _G.os
local term       = _G.term
local textutils  = _G.textutils

local PassThroughCanvas = class()
function PassThroughCanvas:init(args)
	Util.merge(self, args)
end

function PassThroughCanvas:clear(bg, fg)
	local filler = _rep(' ', self.width)
	for i = 1, self.height do
		self:write(1, i, filler, bg, fg)
	end
end

function PassThroughCanvas:write(x, y, text, bg, fg)
	bg = bg or self.window.backgroundColor
	fg = fg or self.window.textColor
	x = x - self.window.offx
	y = y - self.window.offy
	if y <= self.height and y > 0 then
		self.parent:write(
			self.x + x - 1, self.y + y - 1, tostring(text), bg, fg)
	end
end

function PassThroughCanvas:resize(w, h)
	self.width = w
	self.height = h
	self.ex = self.x + self.width - 1
	self.ey = self.y + self.height - 1
end

function PassThroughCanvas:move(x, y)
	self.x, self.y = x, y
	self.ex = self.x + self.width - 1
	self.ey = self.y + self.height - 1
end

function PassThroughCanvas:raise()
end

function PassThroughCanvas:setVisible()
end

--[[
	Using the shorthand window definition, elements are created from
	the bottom up. Once reaching the top, setParent is called top down.

	On :init(), elements do not know the parent or can calculate sizing.

	Calling order:
	window:postInit()
		at this point, the window has all default values set
	window:setParent()
		parent has been assigned
		following are called:
		window:layout()
			sizing / positioning is performed
		window:initChildren()
			each child of window will get initialized
]]

--[[-- Top Level Manager --]]--
local Manager = class()
function Manager:init()
	self.devices = { }
	self.theme = { }
	self.extChars = Util.getVersion() >= 1.76

	local function keyFunction(event, code, held)
		local ie = Input:translate(event, code, held)

		local currentPage = self:getActivePage()
		if ie and currentPage then
			local target = currentPage.focused or currentPage
			self:inputEvent(target,
				{ type = 'key', key = ie.code == 'char' and ie.ch or ie.code, element = target, ie = ie })
			currentPage:sync()
		end
	end

	local function resize(_, side)
		local dev = self.devices[side or 'terminal']
		if dev and dev.currentPage then
			-- the parent doesn't have any children set...
			-- that's why we have to resize both the parent and the current page
			-- kinda makes sense
			dev.currentPage.parent:resize()

			dev.currentPage:resize()
			dev.currentPage:draw()
			dev.currentPage:sync()
		end
	end

	local handlers = {
		char = keyFunction,
		key_up = keyFunction,
		key = keyFunction,
		term_resize = resize,
		monitor_resize = resize,

		mouse_scroll = function(_, direction, x, y)
			local currentPage = self:getActivePage()
			if currentPage then
				local event = currentPage:pointToChild(x, y)
				local directions = {
					[ -1 ] = 'up',
					[  1 ] = 'down'
				}
				-- revisit - should send out scroll_up and scroll_down events
				-- let the element convert them to up / down
				self:inputEvent(event.element,
					{ type = 'key', key = directions[direction] })
				currentPage:sync()
			end
		end,

		monitor_touch = function(_, side, x, y)
			local dev = self.devices[side]
			if dev and dev.currentPage then
				Input:translate('mouse_click', 1, x, y)
				local ie = Input:translate('mouse_up', 1, x, y)
				self:click(dev.currentPage, ie.code, 1, x, y)
			end
		end,

		mouse_click = function(_, button, x, y)
			local ie = Input:translate('mouse_click', button, x, y)

			local currentPage = self:getActivePage()
			if currentPage then
				if not currentPage.parent.device.side then
					local event = currentPage:pointToChild(x, y)
					if event.element.focus and not event.element.inactive then
						currentPage:setFocus(event.element)
						currentPage:sync()
					end
					self:click(currentPage, ie.code, button, x, y)
				end
			end
		end,

		mouse_up = function(_, button, x, y)
			local ie = Input:translate('mouse_up', button, x, y)
			local currentPage = self:getActivePage()

			if ie.code == 'control-shift-mouse_click' then -- hack
				local event = currentPage:pointToChild(x, y)
_G._p = event.element
				_ENV.multishell.openTab({
					path = 'sys/apps/Lua.lua',
					args = { event.element },
					focused = true })

			elseif ie and currentPage then
				if not currentPage.parent.device.side then
					self:click(currentPage, ie.code, button, x, y)
				end
			end
		end,

		mouse_drag = function(_, button, x, y)
			local ie = Input:translate('mouse_drag', button, x, y)
			local currentPage = self:getActivePage()

			if ie and currentPage then
				self:click(currentPage, ie.code, button, ie.dx, ie.dy)
			end
		end,

		paste = function(_, text)
			local ie = Input:translate('paste', text)
			self:emitEvent({ type = 'paste', text = text, ie = ie })
			self:getActivePage():sync()
		end,
	}

	-- use 1 handler to single thread all events
	Event.on({
		'char', 'key_up', 'key', 'term_resize', 'monitor_resize',
		'mouse_scroll', 'monitor_touch', 'mouse_click',
		'mouse_up', 'mouse_drag', 'paste' },
		function(event, ...)
			handlers[event](event, ...)
		end)
end

function Manager:configure(appName, ...)
	local defaults = Util.loadTable('usr/config/' .. appName) or { }
	if not defaults.device then
		defaults.device = { }
	end

	-- starting a program: gpsServer --display=monitor_3148 --scale=.5 gps
	local _, options = Util.parse(...)
	local optionValues = {
		name = options.display,
		textScale = tonumber(options.scale),
	}

	Util.merge(defaults.device, optionValues)

	if defaults.device.name then
		local dev

		if defaults.device.name == 'terminal' then
			dev = term.current()
		else
			dev = device[defaults.device.name]
		end

		if not dev then
			error('Invalid display device')
		end
		self:setDefaultDevice(self.Device({
			device = dev,
			textScale = defaults.device.textScale,
		}))
	end

	if defaults.theme then
		for k,v in pairs(defaults.theme) do
			if self[k] and self[k].defaults then
				Util.merge(self[k].defaults, v)
			end
		end
	end
end

function Manager:disableEffects()
	self.defaultDevice.effectsEnabled = false
end

function Manager:loadTheme(filename)
	if fs.exists(filename) then
		local theme, err = Util.loadTable(filename)
		if not theme then
			error(err)
		end
		Util.deepMerge(self.theme, theme)
	end
end

function Manager:generateTheme(filename)
	local t = { }
	for k,v in pairs(self) do
		if type(v) == 'table' then
			if v._preload then
				v._preload()
				v = self[k]
			end
			if v.defaults and v.defaults.UIElement ~= 'Device' then
				for p,d in pairs(v.defaults) do
					if p:find('olor') then
						if not t[k] then
							t[k] = { }
						end
						for c, n in pairs(colors) do
							if n == d then
								t[k][p] = 'colors.' .. c
								break
							end
						end
					end
				end
			end
		end
	end
	Util.writeFile(filename, textutils.serialize(t):gsub('(")', ''))
end

function Manager:emitEvent(event)
	local currentPage = self:getActivePage()
	if currentPage and currentPage.focused then
		return currentPage.focused:emit(event)
	end
end

function Manager:inputEvent(parent, event) -- deprecate ?
	return parent and parent:emit(event)
end

function Manager:click(target, code, button, x, y)
	local clickEvent

	if code == 'mouse_drag' then
		clickEvent = {
			element = self.__maybeWillDrag,
			x = x,
			y = y,
		}
	else
		clickEvent = target:pointToChild(x, y)

		if code == 'mouse_down' then
			self.__maybeWillDrag = clickEvent.element
		end
	end

	if code == 'mouse_doubleclick' then
		if self.doubleClickElement ~= clickEvent.element then
			return
		end
	else
		self.doubleClickElement = clickEvent.element
	end

	clickEvent.button = button
	clickEvent.type = code
	clickEvent.key = code
	clickEvent.ie = { code = code, x = clickEvent.x, y = clickEvent.y }

	if clickEvent.element.focus then
		target:setFocus(clickEvent.element)
	end
	self:inputEvent(clickEvent.element, clickEvent)

	target:sync()
end

function Manager:setDefaultDevice(dev)
	self.defaultDevice = dev
	self.term = dev
end

function Manager:addPage(name, page)
	if not self.pages then
		self.pages = { }
	end
	self.pages[name] = page
end

function Manager:setPages(pages)
	self.pages = pages
end

function Manager:getPage(pageName)
	local page = self.pages[pageName]

	if not page then
		error('UI:getPage: Invalid page: ' .. tostring(pageName), 2)
	end

	return page
end

function Manager:getActivePage(page)
	if page then
		return page.parent.currentPage
	end
	return self.defaultDevice.currentPage
end

function Manager:setActivePage(page)
	page.parent.currentPage = page
	page.parent.canvas = page.canvas
end

function Manager:setPage(pageOrName, ...)
	local page = pageOrName

	if type(pageOrName) == 'string' then
		page = self.pages[pageOrName] or error('Invalid page: ' .. pageOrName)
	end

	local currentPage = self:getActivePage(page)
	if page == currentPage then
		page:draw()
	else
		if currentPage then
			if currentPage.focused then
				currentPage.focused.focused = false
				currentPage.focused:focus()
			end
			currentPage:disable()
			page.previousPage = currentPage
		end
		self:setActivePage(page)
		--page:clear(page.backgroundColor)
		page:enable(...)
		page:draw()
		if page.focused then
			page.focused.focused = true
			page.focused:focus()
		end
		page:sync()
	end
end

function Manager:getCurrentPage()
	return self.defaultDevice.currentPage
end

function Manager:setPreviousPage()
	if self.defaultDevice.currentPage.previousPage then
		local previousPage = self.defaultDevice.currentPage.previousPage.previousPage
		self:setPage(self.defaultDevice.currentPage.previousPage)
		self.defaultDevice.currentPage.previousPage = previousPage
	end
end

function Manager:getDefaults(element, args)
	local defaults = Util.deepCopy(element.defaults)
	if args then
		Manager:mergeProperties(defaults, args)
	end
	return defaults
end

function Manager:mergeProperties(obj, args)
	if args then
		for k,v in pairs(args) do
			if k == 'accelerators' then
				if obj.accelerators then
					Util.merge(obj.accelerators, args.accelerators)
				else
					obj[k] = v
				end
			else
				obj[k] = v
			end
		end
	end
end

function Manager:pullEvents(...)
	local s, m = pcall(Event.pullEvents, ...)
	self.term:reset()
	if not s and m then
		error(m, -1)
	end
end

function Manager:exitPullEvents()
	Event.exitPullEvents()
end

local UI = Manager()

--[[-- Basic drawable area --]]--
UI.Window = class()
UI.Window.uid = 1
UI.Window.docs = { }
UI.Window.defaults = {
	UIElement = 'Window',
	x = 1,
	y = 1,
	-- z = 0, -- eventually...
	offx = 0,
	offy = 0,
	cursorX = 1,
	cursorY = 1,
}
function UI.Window:init(args)
	-- merge defaults for all subclasses
	local defaults = args
	local m = getmetatable(self)  -- get the class for this instance
	repeat
		defaults = UI:getDefaults(m, defaults)
		m = m._base
	until not m
	UI:mergeProperties(self, defaults)

	-- each element has a unique ID
	self.uid = UI.Window.uid
	UI.Window.uid = UI.Window.uid + 1

	-- at this time, the object has all the properties set

	-- postInit is a special constructor. the element does not need to implement
	-- the method. But we need to guarantee that each subclass which has this
	-- method is called.
	m = self
	local lpi
	repeat
		if m.postInit and m.postInit ~= lpi then
			m.postInit(self)
			lpi = m.postInit
		end
		m = m._base
	until not m
end

function UI.Window:postInit()
	if self.parent then
		-- this will cascade down the whole tree of elements starting at the
		-- top level window (which has a device as a parent)
		self:setParent()
	end
end

function UI.Window:initChildren()
	local children = self.children

	-- insert any UI elements created using the shorthand
	-- window definition into the children array
	for k,child in pairs(self) do
		if k ~= 'parent' then -- reserved
			if type(child) == 'table' and child.UIElement and not child.parent then
				if not children then
					children = { }
				end
				table.insert(children, child)
			end
		end
	end
	if children then
		for _,child in pairs(children) do
			if not child.parent then
				child.parent = self
				child:setParent()
				if self.enabled then
					child:enable()
				end
			end
		end
		self.children = children
	end
end

function UI.Window:layout()
	local function calc(p, max)
		p = tonumber(p:match('(%d+)%%'))
		return p and math.floor(max * p / 100) or 1
	end

	if type(self.x) == 'string' then
		self.x = calc(self.x, self.parent.width) + 1
		-- +1 in order to allow both x and ex to use the same %
	end
	if type(self.ex) == 'string' then
		self.ex = calc(self.ex, self.parent.width)
	end
	if type(self.y) == 'string' then
		self.y = calc(self.y, self.parent.height) + 1
	end
	if type(self.ey) == 'string' then
		self.ey = calc(self.ey, self.parent.height)
	end

	if self.x < 0 then
		self.x = self.parent.width + self.x + 1
	end
	if self.y < 0 then
		self.y = self.parent.height + self.y + 1
	end

	if self.ex then
		local ex = self.ex
		if self.ex <= 1 then
			ex = self.parent.width + self.ex + 1
		end
		if self.width then
			self.x = ex - self.width + 1
		else
			self.width = ex - self.x + 1
		end
	end
	if self.ey then
		local ey = self.ey
		if self.ey <= 1 then
			ey = self.parent.height + self.ey + 1
		end
		if self.height then
			self.y = ey - self.height + 1
		else
			self.height = ey - self.y + 1
		end
	end

	if not self.width then
		self.width = self.parent.width - self.x + 1
	end
	if not self.height then
		self.height = self.parent.height - self.y + 1
	end

	if not self.canvas then
		self.canvas = self:addLayer()

		--[[self.canvas = PassThroughCanvas {
			parent = self.parent,
			window = self,
			x = self.x,
			y = self.y,
			width = self.width,
			height = self.height,
			ex = self.x + self.width - 1,
			ey = self.y + self.height - 1,
		}
		]]

	else
		self.canvas:resize(self.width, self.height)
	end

end

-- Called when the window's parent has be assigned
function UI.Window:setParent()
	-- Experimental
	-- Inherit properties from the parent container
	-- does this need to be in reverse order ?
	local m = getmetatable(self)  -- get the class for this instance
	repeat
		if m.inherits then
			for k, v in pairs(m.inherits) do
				local value = self.parent:getProperty(v)
				if value then
					self[k] = value
				end
			end
		end
		m = m._base
	until not m

	self.oh, self.ow = self.height, self.width
	self.ox, self.oy = self.x, self.y

	self:layout()

	self:initChildren()
end

function UI.Window:move(x, y)
	self.x = x
	self.y = y
	self.canvas:move(x, y)
	--self.parent:draw()
end

function UI.Window:reposition(x, y, w, h)
	if self.width ~= w or self.height ~= h then
		self.height = h
		self.width = w
		self.canvas:resize(w, h)
		for _,v in pairs(self.children) do
			v:resize()
		end
	end
	if self.x ~= x or self.y ~= y then
		self:move(x, y)
	end
end

function UI.Window:resize()
	self.height, self.width = self.oh, self.ow
	self.x, self.y = self.ox, self.oy

	self:layout()

	if self.children then
		for _,child in ipairs(self.children) do
			child:resize()
		end
	end
end

UI.Window.docs.add = [[add(TABLE)
Add element(s) to a window. Example:
page:add({
	text = UI.Text {
	  x=5,value='help'
	}
})]]
function UI.Window:add(children)
	UI:mergeProperties(self, children)
	self:initChildren()
end

function UI.Window:getCursorPos()
	return self.cursorX, self.cursorY
end

function UI.Window:setCursorPos(x, y)
	self.cursorX = x
	self.cursorY = y
	self.parent:setCursorPos(self.x + x - 1, self.y + y - 1)
end

function UI.Window:setCursorBlink(blink)
	self.parent:setCursorBlink(blink)
end

UI.Window.docs.draw = [[draw(VOID)
Redraws the window in the internal buffer.]]
function UI.Window:draw()
	self:clear(self.backgroundColor)
	if self.children then
		for _,child in pairs(self.children) do
			if child.enabled then
				child:draw()
			end
		end
	end
end

UI.Window.docs.getDoc = [[getDoc(STRING method)
Gets the documentation for a method.]]
function UI.Window:getDoc(method)
	local m = getmetatable(self)  -- get the class for this instance
	repeat
		if m.docs and m.docs[method] then
			return m.docs[method]
		end
		m = m._base
	until not m
end

UI.Window.docs.sync = [[sync(VOID)
Invoke a screen update. Automatically called at top level after an input event.
Call to force a screen update.]]
function UI.Window:sync()
	if self.parent then
		self.parent:sync()
	end
end

function UI.Window:enable(...)
	self.enabled = true
	self.canvas:setVisible(true)
	if self.children then
		for _,child in pairs(self.children) do
			child:enable(...)
		end
	end
end

function UI.Window:disable()
	self.enabled = false
	if self.children then
		for _,child in pairs(self.children) do
			child:disable()
		end
	end
end

function UI.Window:setTextScale(textScale)
	self.textScale = textScale
	self.parent:setTextScale(textScale)
end

UI.Window.docs.clear = [[clear(opt COLOR bg, opt COLOR fg)
Clears the window using the either the passed values or the defaults for that window.]]
function UI.Window:clear(bg, fg)
	self.canvas:clear(bg or self:getProperty('backgroundColor'), fg or self:getProperty('textColor'))
end

function UI.Window:clearLine(y, bg)
	self:write(1, y, _rep(' ', self.width), bg)
end

function UI.Window:clearArea(x, y, width, height, bg)
	if width > 0 then
		local filler = _rep(' ', width)
		for i = 0, height - 1 do
			self:write(x, y + i, filler, bg)
		end
	end
end

function UI.Window:write(x, y, text, bg, fg)
	bg = bg or self.backgroundColor
	fg = fg or self.textColor
	self.canvas:write(x, y, text, bg or self:getProperty('backgroundColor'), fg or self:getProperty('textColor'))
end

function UI.Window:centeredWrite(y, text, bg, fg)
	if #text >= self.width then
		self:write(1, y, text, bg, fg)
	else
		local space = math.floor((self.width-#text) / 2)
		local filler = _rep(' ', space + 1)
		local str = _sub(filler, 1, space) .. text
		str = str .. _sub(filler, self.width - #str + 1)
		self:write(1, y, str, bg, fg)
	end
end

function UI.Window:print(text, bg, fg)
	local marginLeft = self.marginLeft or 0
	local marginRight = self.marginRight or 0
	local width = self.width - marginLeft - marginRight

	local function nextWord(line, cx)
		local result = { line:find("(%w+)", cx) }
		if #result > 1 and result[2] > cx then
			return _sub(line, cx, result[2] + 1)
		elseif #result > 0 and result[1] == cx then
			result = { line:find("(%w+)", result[2]) }
			if #result > 0 then
				return _sub(line, cx, result[1] + 1)
			end
		end
		if cx <= #line then
			return _sub(line, cx, #line)
		end
	end

	local function pieces(f, bg, fg)
		local pos = 1
		local t = { }
		while true do
			local s = string.find(f, '\027', pos, true)
			if not s then
				break
			end
			if pos < s then
				table.insert(t, _sub(f, pos, s - 1))
			end
			local seq = _sub(f, s)
			seq = seq:match("\027%[([%d;]+)m")
			local e = { }
			for color in string.gmatch(seq, "%d+") do
				color = tonumber(color)
				if color == 0 then
					e.fg = fg
					e.bg = bg
				elseif color > 20 then
					e.bg = 2 ^ (color - 21)
				else
					e.fg = 2 ^ (color - 1)
				end
			end
			table.insert(t, e)
			pos = s + #seq + 3
		end
		if pos <= #f then
			table.insert(t, _sub(f, pos))
		end
		return t
	end

	local lines = Util.split(text)
	for k,line in pairs(lines) do
		local fragments = pieces(line, bg, fg)
		for _, fragment in ipairs(fragments) do
			local lx = 1
			if type(fragment) == 'table' then -- ansi sequence
				fg = fragment.fg
				bg = fragment.bg
			else
				while true do
					local word = nextWord(fragment, lx)
					if not word then
						break
					end
					local w = word
					if self.cursorX + #word > width then
						self.cursorX = marginLeft + 1
						self.cursorY = self.cursorY + 1
						w = word:gsub('^ ', '')
					end
					self:write(self.cursorX, self.cursorY, w, bg, fg)
					self.cursorX = self.cursorX + #w
					lx = lx + #word
				end
			end
		end
		if lines[k + 1] then
			self.cursorX = marginLeft + 1
			self.cursorY = self.cursorY + 1
		end
	end

	return self.cursorX, self.cursorY
end

UI.Window.docs.focus = [[focus(VOID)
If the function is present on a class, it indicates
that this element can accept focus. Called when receiving focus.]]

UI.Window.docs.setFocus = [[setFocus(ELEMENT el)
Set the page's focus to the passed element.]]
function UI.Window:setFocus(focus)
	if self.parent then
		self.parent:setFocus(focus)
	end
end

UI.Window.docs.capture = [[capture(ELEMENT el)
Restricts input to the passed element's tree.]]
function UI.Window:capture(child)
	if self.parent then
		self.parent:capture(child)
	end
end

function UI.Window:release(child)
	if self.parent then
		self.parent:release(child)
	end
end

function UI.Window:pointToChild(x, y)
	-- TODO: get rid of this offx/y mess and scroll canvas instead
	x = x + self.offx - self.x + 1
	y = y + self.offy - self.y + 1

	if self.children then
if Util.size(self.children) ~= #self.children then
	error('children is not an array')
end
		for i = #self.children, 1, -1 do
			local child = self.children[i]
			if child.enabled and not child.inactive and
				 x >= child.x and x < child.x + child.width and
				 y >= child.y and y < child.y + child.height then
				local c = child:pointToChild(x, y)
				if c then
					return c
				end
			end
		end
	end
	return {
		element = self,
		x = x,
		y = y
	}
end

UI.Window.docs.getFocusables = [[getFocusables(VOID)
Returns a list of children that can accept focus.]]
function UI.Window:getFocusables()
	local focusable = { }

	local function focusSort(a, b)
		if a.y == b.y then
			return a.x < b.x
		end
		return a.y < b.y
	end

	local function getFocusable(parent)
		for _,child in Util.spairs(parent.children, focusSort) do
			if child.enabled and child.focus and not child.inactive then
				table.insert(focusable, child)
			end
			if child.children then
				getFocusable(child)
			end
		end
	end

	if self.children then
		getFocusable(self, self.x, self.y)
	end

	return focusable
end

function UI.Window:focusFirst()
	local focusables = self:getFocusables()
	local focused = focusables[1]
	if focused then
		self:setFocus(focused)
	end
end

function UI.Window:refocus()
	local el = self
	while el do
		local focusables = el:getFocusables()
		if focusables[1] then
			self:setFocus(focusables[1])
			break
		end
		el = el.parent
	end
end

function UI.Window:scrollIntoView()
	local parent = self.parent

	if self.x <= parent.offx then
		parent.offx = math.max(0, self.x - 1)
		parent:draw()
	elseif self.x + self.width > parent.width + parent.offx then
		parent.offx = self.x + self.width - parent.width - 1
		parent:draw()
	end

	-- TODO: fix
	local function setOffset(y)
		parent.offy = y
		if parent.canvas then
			parent.canvas.offy = parent.offy
		end
		parent:draw()
	end

	if self.y <= parent.offy then
		setOffset(math.max(0, self.y - 1))
	elseif self.y + self.height > parent.height + parent.offy then
		setOffset(self.y + self.height - parent.height - 1)
	end
end

function UI.Window:raise()
	local w = Util.contains(self.parent.children, self)
	if self ~= self.parent.children[#self.parent.children] then
		table.remove(self.parent.children, w)
		table.insert(self.parent.children, self)
		self.canvas:raise()
		self:draw()
	end
end

function UI.Window:getCanvas()
	local el = self
	repeat
		if el.canvas and el.canvas.layers then
			return el.canvas
		end
		el = el.parent
	until not el
end

function UI.Window:addLayer(bg, fg)
	local canvas = self:getCanvas()
	local x, y = self.x, self.y
	local parent = self.parent
	while parent and not (parent.canvas and parent.canvas.layers) do
		x = x + parent.x - 1
		y = y + parent.y - 1
		parent = parent.parent
	end
	canvas = canvas:addLayer({
		x = x, y = y, height = self.height, width = self.width
	}, bg, fg)

	canvas:clear(bg or self.backgroundColor, fg or self.textColor)
	return canvas
end

function UI.Window:addTransition(effect, args)
	if self.parent then
		args = args or { }
		if not args.x then -- not good
			args.x, args.y = self.x, self.y -- getPosition(self)
			args.width = self.width
			args.height = self.height
		end

		args.canvas = args.canvas or self.canvas
		self.parent:addTransition(effect, args)
	end
end

function UI.Window:emit(event)
	local parent = self
	while parent do
		if parent.accelerators then
			-- events types can be made unique via accelerators
			local acc = parent.accelerators[event.key or event.type]
			if acc and acc ~= event.type then -- don't get stuck in a loop
				local event2 = Util.shallowCopy(event)
				event2.type = acc
				event2.key = nil
				if parent:emit(event2) then
					return true
				end
			end
		end
		if parent.eventHandler then
			if parent:eventHandler(event) then
				return true
			end
		end
		parent = parent.parent
	end
end

function UI.Window:getProperty(property)
	return self[property] or self.parent and self.parent:getProperty(property)
end

function UI.Window:find(uid)
	return self.children and Util.find(self.children, 'uid', uid)
end

function UI.Window:eventHandler()
	return false
end

--[[-- Terminal for computer / advanced computer / monitor --]]--
UI.Device = class(UI.Window)
UI.Device.defaults = {
	UIElement = 'Device',
	backgroundColor = colors.black,
	textColor = colors.white,
	textScale = 1,
	effectsEnabled = true,
}
function UI.Device:postInit()
	self.device = self.device or term.current()

	--if self.deviceType then
	--	self.device = device[self.deviceType]
	--end

	if not self.device.setTextScale then
		self.device.setTextScale = function() end
	end

	self.device.setTextScale(self.textScale)
	self.width, self.height = self.device.getSize()

	self.isColor = self.device.isColor()

	UI.devices[self.device.side or 'terminal'] = self
end

function UI.Device:resize()
	self.device.setTextScale(self.textScale)
	self.width, self.height = self.device.getSize()
	self.lines = { }
	-- TODO: resize all pages added to this device
	self.canvas:resize(self.width, self.height)
	self.canvas:clear(self.backgroundColor, self.textColor)
end

function UI.Device:setCursorPos(x, y)
	self.cursorX = x
	self.cursorY = y
end

function UI.Device:getCursorBlink()
	return self.cursorBlink
end

function UI.Device:setCursorBlink(blink)
	self.cursorBlink = blink
	self.device.setCursorBlink(blink)
end

function UI.Device:setTextScale(textScale)
	self.textScale = textScale
	self.device.setTextScale(self.textScale)
end

function UI.Device:reset()
	self.device.setBackgroundColor(colors.black)
	self.device.setTextColor(colors.white)
	self.device.clear()
	self.device.setCursorPos(1, 1)
end

function UI.Device:addTransition(effect, args)
	if not self.transitions then
		self.transitions = { }
	end

	args = args or { }
	args.ex = args.x + args.width - 1
	args.ey = args.y + args.height - 1
	args.canvas = args.canvas or self.canvas

	if type(effect) == 'string' then
		effect = Transition[effect]
		if not effect then
			error('Invalid transition')
		end
	end

	table.insert(self.transitions, { update = effect(args), args = args })
end

function UI.Device:runTransitions(transitions, canvas)
	while true do
		for _,k in ipairs(Util.keys(transitions)) do
			local transition = transitions[k]
			if not transition.update() then
				transitions[k] = nil
			end
		end
		canvas:render(self.device)
		if Util.empty(transitions) then
			break
		end
		os.sleep(0)
	end
end

function UI.Device:sync()
	local transitions = self.effectsEnabled and self.transitions
	self.transitions = nil

	if self:getCursorBlink() then
		self.device.setCursorBlink(false)
	end

	self.canvas:render(self.device)
	if transitions then
		self:runTransitions(transitions, self.canvas)
	end

	if self:getCursorBlink() then
		self.device.setCursorPos(self.cursorX, self.cursorY)
		self.device.setCursorBlink(true)
	end
end

-- lazy load components
local function loadComponents()
	local function load(name)
		local s, m = Util.run(_ENV, 'sys/modules/opus/ui/components/' .. name .. '.lua')
		if not s then
			error(m)
		end
		if UI[name]._preload then
			error('Error loading UI.' .. name)
		end
		if UI.theme[name] and UI[name].defaults then
			Util.merge(UI[name].defaults, UI.theme[name])
		end
		return UI[name]
	end

	local components = fs.list('sys/modules/opus/ui/components')
	for _, f in pairs(components) do
		local name = f:match('(.+)%.')

		UI[name] = setmetatable({ }, {
			__call = function(self, ...)
				load(name)
				setmetatable(self, getmetatable(UI[name]))
				return self(...)
			end
		})
		UI[name]._preload = function(self)
			return load(name)
		end
	end
end

loadComponents()
UI:loadTheme('usr/config/ui.theme')
Util.merge(UI.Window.defaults, UI.theme.Window)
UI:setDefaultDevice(UI.Device({ device = term.current() }))

return UI
