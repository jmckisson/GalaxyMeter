--
-- Created by IntelliJ IDEA.
-- User: John
-- Date: 1/26/14
-- Time: 9:46 PM
--

require "Apollo"
require "Window"


local DerpsWindow  = {}
DerpsWindow.__index = DerpsWindow


function DerpsWindow:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self



	return o
end


function DerpsWindow:InitUI(xmlDoc)

	-- Load Forms
	self.wndMain = Apollo.LoadForm(self.xmlDoc, "DerpsWindow", nil, self)
	self.wndMain:Show(false)
	self.wndEncList = self.wndMain:FindChild("EncounterList")
	self.wndEncList:Show(false)

	-- Store Child Widgets
	self.Children = {}
	self.Children.TimeText = self.wndMain:FindChild("Time_Text")
	self.Children.DisplayText = self.wndMain:FindChild("Display_Text")
	self.Children.EncounterButton = self.wndMain:FindChild("EncounterButton")
	self.Children.ModeButton_Left = self.wndMain:FindChild("ModeButton_Left")
	self.Children.ModeButton_Right = self.wndMain:FindChild("ModeButton_Right")
	self.Children.ConfigButton = self.wndMain:FindChild("ConfigButton")
	self.Children.ClearButton = self.wndMain:FindChild("ClearButton")
	self.Children.CloseButton = self.wndMain:FindChild("CloseButton")
	self.Children.EncItemList = self.wndEncList:FindChild("ItemList")

	self.Children.EncounterButton:SetText("")
	self.Children.TimeText:SetText("")
	self.Children.DisplayText:SetText("")

	-- Item List
	self.wndItemList = self.wndMain:FindChild("ItemList")


	-- modes
	self.tMode = self.tModes["Main Menu"]   -- Default to Main Menu
	self.nLogIndex = 0

	-- References to log entry held by the main Derps instance
	self.tLogDisplay = nil

	self.tItems = {} -- keep track of all the list items
	self.tEncItems = {}
	self.DisplayOrder = {}
end


function DerpsWindow:GetLogDisplay()
	return self.tLogDisplay
end


-----------------------------------------------------------------------------------------------
-- ItemList Functions
-----------------------------------------------------------------------------------------------

-- clear the item list
function DerpsWindow:DestroyItemList()
	-- destroy all the wnd inside the list
	for idx,wnd in ipairs(self.tItems) do
		wnd:Destroy()
	end

	-- clear the list item array
	self.tItems = {}
end


-- add an item into the item list
function DerpsWindow:AddItem(i)
	-- load the window item for the list item
	local wnd = Apollo.LoadForm(self.xmlDoc, "ListItem", self.wndItemList, self)

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


function DerpsWindow:CompareDisplay(Index, Text)
	if not self.DisplayOrder[Index] or ( self.DisplayOrder[Index] and self.DisplayOrder[Index] ~= Text ) then
		self.DisplayOrder[Index] = Text
		return true
	end
end


-- Main list display function, this will assemble list items and set their click handler
-- TODO Maybe combine this with Get*List or something to avoid so much looping?
function DerpsWindow:DisplayList(Listing)

	--self:Rover("DisplayList: List", Listing)

	local Arrange = false
	for k,v in ipairs(Listing) do
		if not self.tItems[k] then
			self:AddItem(k)
		end

		local wnd = self.tItems[k]

		if self:CompareDisplay(k, v.n) then
			--gLog:info(string.format("CompareDisplay true tItem[%s] n=%s", k, v.n))
			wnd.id = wnd.wnd:GetId()
			wnd.left_text:SetText(v.n)
			wnd.bar:SetBarColor(v.c)
			Arrange = true
		end

		wnd.OnClick = v.click

		if v.t then
			-- TODO move formatting into the list generator
			-- v.t is a total, format a string showing the total and total over time as dps
			wnd.right_text:SetText(string.format("%s (%.2f)", v.t, v.t / self:GetLogDisplayTimer()))

			wnd.bar:SetProgress(v.t / Listing[1].t)
		else
			-- v.tStr is a preformatted total string
			if v.tStr then
				wnd.right_text:SetText(v.tStr)
			else
				wnd.right_text:SetText("")
			end
			wnd.bar:SetProgress(1)
		end
	end

	-- Trim Remainder
	if #self.tItems > #Listing then
		for i=#Listing+1, #self.tItems do
			self.tItems[i].wnd:Destroy()
			self.tItems[i] = nil
		end
	end

	-- Rearrange if list order changed
	if Arrange then
		self.wndItemList:ArrangeChildrenVert()
	end
end


function DerpsWindow:HideEncounterDropDown()
	self.tEncItems = {}
	self.Children.EncItemList:DestroyChildren()
	self.wndEncList:Show(false)
end


function DerpsWindow:SecondsToString(time)
	local Min = math.floor(time / 60)
	local Sec = time % 60

	local Time_String = ""
	if time >= 60 then
		Time_String = string.format("%sm:%.0fs", Min , Sec )
	else
		Time_String = string.format("%.2fs", Sec )
	end
	return Time_String
end


function DerpsWindow:DisplayUpdate()

	local mode = self.vars.tMode

	if not mode.display then
		return
	end

	local tList, tTotal, strDisplayText = mode.display(self)	-- Self reference needed for calling object method

	if mode.sort ~= nil then
		table.sort(tList, mode.sort)
	end

	-- if option to show totals
	if tTotal ~= nil then
		tTotal.n = strDisplayText
		tTotal.click = function(m, btn)
			if btn == 1 then
				local tMode = self:PopMode()
				if tMode then
					self.vars.tMode = tMode
					self.bDirty = true
				end
			end
		end

		table.insert(tList, 1, tTotal)
	end

	-- Text below the meter
	self.Children.DisplayText:SetText(strDisplayText)

	self:DisplayList(tList)
end



function DerpsWindow:RefreshDisplay()
	self.DisplayOrder = {}
	self:DisplayUpdate()
end
