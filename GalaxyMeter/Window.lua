--
-- Created by IntelliJ IDEA.
-- User: John
-- Date: 3/23/14
-- Time: 10:39 AM
--

local GM = Apollo.GetAddon("GalaxyMeter")
local Window = {}

local xmlMainDoc = XmlDoc.CreateFromFile("GalaxyMeter.xml")

function Window:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self

	return o
end


function Window:Init()

	-- Load Forms
	--self.xmlMainDoc = XmlDoc.CreateFromFile("GalaxyMeter.xml")

	self.wndMain = Apollo.LoadForm(xmlMainDoc, "GalaxyMeterForm", nil, self)
	self.wndMain:Show(false)
	self.wndEncList = self.wndMain:FindChild("EncounterList")
	self.wndEncList:Show(false)

	-- Store Child Widgets
	self.Children = {}
	self.Children.TimeText = self.wndMain:FindChild("Time_Text")
	self.Children.DisplayText = self.wndMain:FindChild("Display_Text")
	self.Children.EncounterText = self.wndMain:FindChild("EncounterText")
	self.Children.ModeButton_Left = self.wndMain:FindChild("ModeButton_Left")
	self.Children.ModeButton_Right = self.wndMain:FindChild("ModeButton_Right")
	self.Children.ConfigButton = self.wndMain:FindChild("ConfigButton")
	self.Children.ClearButton = self.wndMain:FindChild("ClearButton")
	self.Children.CloseButton = self.wndMain:FindChild("CloseButton")
	self.Children.EncItemList = self.wndEncList:FindChild("ItemList")

	self.Children.EncounterText:SetText("")
	self.Children.TimeText:SetText("")
	self.Children.DisplayText:SetText("")

	-- Item List
	self.wndItemList = self.wndMain:FindChild("ItemList")

	self.tItems = {}
	self.tEncItems = {}

	-- Display Order (For Reducing On Screen Drawing)
	self.DisplayOrder = {}

	self.bDirty = false
	self.tMode = GM.tModes["Main Menu"]
	self.nLogIndex = 0
	self.tLogDisplay = GM:GetLog()


end


function Window:OnOK()
	self.wndMain:Show(false) -- hide the window
end


-- when the Cancel button is clicked
function Window:OnCancel()
	self.wndMain:Show(false) -- hide the window
end


function Window:Dirty(val)
	if val then
		self.bDirty = val
	end

	return self.bDirty
end

function Window:LogActor(tActor)
	if tActor then
		self.tLogActor = tActor
	end

	return self.vars.tLogActor
end


function Window:LogActorId(nId)
	if nId then
		self.nCurrentActorId = nId
	end

	return self.vars.nCurrentActorId
end


function Window:LogActorName(str)
	if str then
		self.strCurrentPlayerName = str
	end

	return self.vars.strCurrentPlayerName
end


function Window:GetCurrentMode()
	return self.tMode
end


function Window:LogSpell(tSpell)
	if tSpell then
		self.tLogSpell = tSpell
	end

	return self.tLogSpell
end


function Window:LogType(str)
	if str then
		self.strCurrentLogType = str
	end

	return self.strCurrentLogType
end


function Window:LogModeType(str)
	if str then
		self.strModeType = str
	end

	return self.strModeType
end


-- Entry point from Report UI button
-- Report current log to X channel
function Window:OnReport( wndHandler, wndControl, eMouseButton )

	local mode = self.tMode

	if not mode.display or not mode.report then
		return
	end

	local tReportStrings = mode.report(self, mode.display(self))

	local strChan = GM:ReportChannel()
	local nLines = GM:ReportLines() + 1

	for i = 1, math.min(#tReportStrings, nLines) do
		ChatSystemLib.Command("/" .. strChan .. " " .. tReportStrings[i])
	end

end


function Window:GetLogDisplay()
	return self.tLogDisplay
end


-- @return LogDisplayTimer, or nil
function Window:GetLogDisplayTimer()
	return self.tLogDisplay.combat_length
end


function Window:SetLogTitle(title)
	if self.tCurrentLog.name == "" then
		self.tCurrentLog.name = title
		if self.tCurrentLog == self.tLogDisplay then
			self.Children.EncounterText:SetText(title)
		end
	end
end


function Window:GetMode()
	return self.tMode
end


-- Pop last mode off of the stack
function Window:PopMode()

	if self.tModeLast and #self.tModeLast > 0 then
		local mode = table.remove(self.tModeLast)
		--gLog:info(self.vars.tModeLast)
		return mode
	end

	return nil
end


-- Push mode onto the stack
function Window:PushMode(tNewMode)
	self.tModeLast = self.tModeLast or {}

	table.insert(self.tModeLast, self.tMode)

	self.tMode = tNewMode
end


function Window:DisplayUpdate()

	local mode = self.vars.tMode

	if not mode.display then
		return
	end

	-- Self reference needed for calling object method
	local tList, tTotal, strDisplayText = mode.display(self)

	if mode.sort ~= nil then
		table.sort(tList, mode.sort)
	end

	-- if option to show totals
	if tTotal ~= nil then
		if not tTotal.n then
			tTotal.n = strDisplayText
		end
		if tTotal.click == nil then
			tTotal.click = function(m, btn)
				if btn == 1 and mode.prev then
					--gLog:info("Totals prev")
					mode.prev(self)
				end
			end
		end

		table.insert(tList, 1, tTotal)
	end

	-- Text below the meter
	self.Children.DisplayText:SetText(strDisplayText)

	self:DisplayList(tList)
end



function Window:RefreshDisplay()
	self.DisplayOrder = {}
	self:DisplayUpdate()
end


function Window:CompareDisplay(Index, Text)
	if not self.DisplayOrder[Index] or ( self.DisplayOrder[Index] and self.DisplayOrder[Index] ~= Text ) then
		self.DisplayOrder[Index] = Text
		return true
	end
end


-- Main list display function, this will assemble list items and set their click handler
function Window:DisplayList(Listing)

	local Arrange = false
	for k, v in ipairs(Listing) do
		if not self.tItems[k] then
			self:AddItem(k)
		end

		local wnd = self.tItems[k]

		if self:CompareDisplay(k, v.n) then
			wnd.id = wnd.wnd:GetId()
			wnd.left_text:SetText(v.n)
			wnd.bar:SetBarColor(v.c)
			Arrange = true
		end

		wnd.OnClick = v.click
		wnd.right_text:SetText(v.tStr)
		wnd.bar:SetProgress(v.progress)
	end

	-- Trim Remainder
	if #self.tItems > #Listing then
		for i = #Listing + 1, #self.tItems do
			self.tItems[i].wnd:Destroy()
			self.tItems[i] = nil
		end
	end

	-- Rearrange if list order changed
	if Arrange then
		self.wndItemList:ArrangeChildrenVert()
	end
end


-- when the Clear button is clicked
function Window:OnClearAll()

	self.vars = {
		nLogIndex = 0,
		tLogDisplay = self.tCurrentLog,
		strCurrentLogType = "",
		strCurrentPlayerName = "",
		strCurrentSpellName = "",
		strModeType = "",
		tMode = self.tModes["Main Menu"],
		tModeLast = {}
	}
	self.Children.EncounterText:SetText(self.tLogDisplay.name)
	self.Children.TimeText:SetText(self:SecondsToString(self.tLogDisplay.combat_length))
	self:RefreshDisplay()
end


function Window:OnEncounterDropDown( wndHandler, wndControl, eMouseButton )
	if not self.wndEncList:IsVisible() then
		self.wndEncList:Show(true)

		-- Newest Entry at the Top
		for i = 1, #self.log do
			local wnd = Apollo.LoadForm(xmlMainDoc, "EncounterItem", self.Children.EncItemList, self)
			table.insert(self.tEncItems, wnd)

			local TimeString = self:SecondsToString(self.log[i].combat_length)

			wnd:FindChild("Text"):SetText(self.log[i].name .. " - " .. TimeString)
			wnd:FindChild("Highlight"):Show(false)
			wnd:SetData(i)
		end
		self.Children.EncItemList:ArrangeChildrenVert()
	else
		self:HideEncounterDropDown()
	end
end


function Window:HideEncounterDropDown()
	self.tEncItems = {}
	self.Children.EncItemList:DestroyChildren()
	self.wndEncList:Show(false)
end


function Window:SecondsToString(time)
	local Min = math.floor(time / 60)
	local Sec = time % 60

	local Time_String = ""
	if time >= 60 then
		Time_String = string.format("%sm:%.0fs", Min , Sec )
	else
		Time_String = string.format("%.1fs", Sec )
	end
	return Time_String
end


-----------------------------------------------------------------------------------------------
-- ItemList Functions
-----------------------------------------------------------------------------------------------
-- clear the item list
function Window:DestroyItemList()
	-- destroy all the wnd inside the list
	for idx,wnd in pairs(self.tItems) do
		wnd:Destroy()
	end

	-- clear the list item array
	self.tItems = {}
end


-- add an item into the item list
function Window:AddItem(i)
	-- load the window item for the list item
	local wnd = Apollo.LoadForm(xmlMainDoc, "ListItem", self.wndItemList, self)

	-- keep track of the window item created
	self.tItems[i] = { wnd = wnd }

	local item = self.tItems[i]

	item.id = wnd:GetId()
	item.bar = wnd:FindChild("PercentBar")
	item.left_text = wnd:FindChild("LeftText")
	item.right_text = wnd:FindChild("RightText")

	item.bar:SetMax(1)
	item.bar:SetProgress(0)
	item.left_text:SetTextColor(kcrNormalText)

	wnd:FindChild("Highlight"):Show(false)

	wnd:SetData(i)

	return self.tItems[i]
end


function Window:OnListItemMouseEnter( wndHandler, wndControl, x, y )
	wndHandler:FindChild("Highlight"):Show(true)
end


function Window:OnListItemMouseExit( wndHandler, wndControl, x, y )
	wndHandler:FindChild("Highlight"):Show(false)
end


function Window:OnListItemButtonUp( wndHandler, wndControl, eMouseButton, nLastRelativeMouseX, nLastRelativeMouseY )
	if self.tListItemClicked == wndControl then
		self.tListItemClicked = nil
		--gLog:info(string.format("control %s id %d, name '%s', button %d", tostring(wndControl), wndControl:GetId(), wndControl:GetName(), tostring(eMouseButton)))

		local id = wndControl:GetId()

		-- find menu item from id of clicked control
		for i, v in pairs(self.tItems) do

			if v.id == id and v.OnClick then
				v.OnClick(self, eMouseButton)
				if self.bDirty then
					self.bDirty = false
					self:RefreshDisplay()
				end
			end

		end
	end
end


function Window:OnListItemButtonDown( wndHandler, wndControl, eMouseButton, nLastRelativeMouseX, nLastRelativeMouseY, bDoubleClick, bStopPropagation )
	self.tListItemClicked = wndControl
end


---------------------------------------------------------------------------------------------------
-- EncounterItem Functions
---------------------------------------------------------------------------------------------------

function Window:OnEncounterItemSelected( wndHandler, wndControl, eMouseButton, nLastRelativeMouseX, nLastRelativeMouseY )
	local logIdx = wndHandler:GetData()

	self.tLogDisplay = GM:GetLog(logIdx)
	-- Should we do a sanity check on the current mode? For now just force back to main menu
	self.tMode = GM.tModes["Main Menu"]
	self.tModeLast = {}

	self.Children.EncounterText:SetText(self.tLogDisplay.name)

	self:HideEncounterDropDown()

	-- Right now this only updates in OnTimer, should probably look at the bDirty logic and move it into RefreshDisplay
	self.Children.TimeText:SetText(self:SecondsToString(self.tLogDisplay.combat_length))

	self.bDirty = true
	self:RefreshDisplay()
end


function Window:OnEncounterItemMouseEnter( wndHandler, wndControl, x, y )
	wndHandler:FindChild("Highlight"):Show(true)
end


function Window:OnEncounterItemMouseExit( wndHandler, wndControl, x, y )
	wndHandler:FindChild("Highlight"):Show(false)
end


GM.Window = Window:new()