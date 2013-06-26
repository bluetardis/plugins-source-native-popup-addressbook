--*********************************************************************************************
-- ====================================================================
-- Corona SDK "Address Book" Sample Code
-- ====================================================================
--
-- File: main.lua
--
-- Version 1.0
--
-- Copyright (C) 2013 Corona Labs Inc. All Rights Reserved.
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy of 
-- this software and associated documentation files (the "Software"), to deal in the 
-- Software without restriction, including without limitation the rights to use, copy, 
-- modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, 
-- and to permit persons to whom the Software is furnished to do so, subject to the 
-- following conditions:
-- 
-- The above copyright notice and this permission notice shall be included in all copies 
-- or substantial portions of the Software.
-- 
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, 
-- INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR 
-- PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE 
-- FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR 
-- OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER 
-- DEALINGS IN THE SOFTWARE.
--
-- Published changes made to this software and associated documentation and module files (the
-- "Software") may be used and distributed by Corona Labs, Inc. without notification. Modifications
-- made to this software and associated documentation and module files may or may not become
-- part of an official software release. All modifications made to the software will be
-- licensed under these same terms and conditions.
--*********************************************************************************************

-- Require the widget library
local widget = require("widget");

-- Set the status bar to show the default iOS status bar
display.setStatusBar( display.DefaultStatusBar )

-- Display a background.
local background = display.newImage( "background.png", true )
background.x = display.contentCenterX
background.y = display.contentCenterY

-- Create a gradient for the top-half of the toolbar
local toolbarGradient = graphics.newGradient( {168, 181, 198, 255 }, {139, 157, 180, 255}, "down" )

-- Create toolbar to go at the top of the screen
local titleBar = display.newRect( 0, display.statusBarHeight, display.contentWidth, 44 )
titleBar:setFillColor( toolbarGradient )

-- Create embossed text to go on the toolbar
local titleText = display.newEmbossedText( "Address Book Demo", 0, 0, native.systemFontBold, 20 )
titleText:setReferencePoint( display.CenterReferencePoint )
titleText:setTextColor( 255 )
titleText.x = 160
titleText.y = titleBar.y

-- Forward reference for chosen action
local action = nil;

-- Pick contact options
local pickContactOptions = 
{
	option = "pickContact",
	-- If true, then the address book will be dismissed upon selecting a contact. 
	hideDetails = true,
	-- If true then tapping/touching a contacts phone number or email will perform the default iOS action (such as call contact, show the compose email popup).
	performDefaultAction = true,
	
	-- Items to show in the detail view section of a contact.
	filter = 
	{
		"phone", "email",
		"birthday",
	}
	
}

-- View contact options
local viewContactOptions = 
{
	option = "viewContact",
	-- If true then tapping/touching a contacts phone number or email will perform the default iOS action (such as call contact, show the compose email popup).
	performDefaultAction = true,
	-- Specifies whether the user can edit the person’s information.
	isEditable = true,
	-- (Required) Name of the contact you wish to view.
	name = "Appleseed",
	
	-- Items to show in the detail view section of a contact.
	filter =
	{
		"email", "birthday",
	}
}

-- New contact options
local newContactOptions =
{
	option = "newContact",
	-- (Required) table containing key/value pairs to pre-fill a new contact's details with.
	data = 
	{
		firstName = "John", lastName = "Doe", 
		organization = "Corona Labs", 
		homePhone = "939222832", workPhone = "939392832", 
		homeEmail = "jondoe@someorganization.com", workEmail = "johndoe@home.com",
	}	
}

-- Unknown contact options
local unknownContactOptions = 
{
	option = "unknownContact",
	-- If true then tapping/touching a contacts phone number or email will perform the default iOS action (such as call contact, show the compose email popup).
	performDefaultAction = false,
	-- Specifies whether buttons appear to let the user perform actions such as sharing the contact, initiating a FaceTime call, or sending a text message.
	allowsActions = true,
	-- The person record is only added to the address book database if allowsAdding is true and the user taps the “Add to Existing Contact” or “Create New Contact” button.
	allowsAdding = false,
	-- Provides a value that is displayed instead of the first and last name.
	alternateName = "Corona Labs",
	-- Text displayed below alternateName.
	message = "Software Company",
	
	-- (Required) table containing key/value pairs to ammend to a contact or to create a new contact with.
	data = 
	{
		organization = "Corona Labs", 
		homePhone = "939222832", workPhone = "939392832", 
		workEmail = "fake@coronalabs.com", homeEmail = "fake@home.com",
	},
}

-- Function to execute on completion of the address book ( ie. when it is dismissed )
local function onComplete( event )	
	print( "event.name:", event.name );
	print( "event.type:", event.type );
	
	-- event.data is either a table or nil depending on the option chosen
	print ( "event.data:", event.data );
	
	-- If there is event.data print it's key/value pairs
	if event.data then
		print( "event.data: {" );
		
		for k, v in pairs( event.data ) do
			print( k , ":" , v );
		end	
		
		print( "}" );
	end
end

-- Execute the chosen popup
local function handleButtons(event)
	local chosenOption = event.target.id
		
	-- Pick contact
	if chosenOption == "pickContact" then
		action = native.showPopup( "addressBook", pickContactOptions, onComplete );
	
	-- View contact
	elseif chosenOption == "viewContact" then
		action = native.showPopup( "addressBook", viewContactOptions, onComplete );
	
	-- Create new contact
	elseif chosenOption == "newContact" then
		action = native.showPopup( "addressBook", newContactOptions, onComplete );

	-- View Unknown contact
	elseif chosenOption == "unknownContact" then
		action = native.showPopup( "addressBook", unknownContactOptions, onComplete );
	end
end


-- Create buttons to handle displaying the correct Address Book option
local displayPicker = widget.newButton
{
	id = "pickContact",
    left = 100,
    top = 200,
    label = "Display Picker",
    font = native.systemFontBold,
    fontSize = 18,
    width = 300, height = 50,
    onRelease = handleButtons
}
displayPicker.x, displayPicker.y = display.contentCenterX, display.screenOriginY + 130;


local newContact = widget.newButton
{
	id = "newContact",
    left = 100,
    top = 200,
    label = "Create New Contact",
    font = native.systemFontBold,
    fontSize = 18,
    width = 300, height = 50,
    onRelease = handleButtons
}
newContact.x, newContact.y = display.contentCenterX, displayPicker.y + displayPicker.contentHeight * 1.5;


local viewContact = widget.newButton
{
	id = "viewContact",
    left = 100,
    top = 200,
    label = "Display and Edit Contact",
    font = native.systemFontBold,
    fontSize = 18,
    width = 300, height = 50,
    onRelease = handleButtons
}
viewContact.x, viewContact.y = display.contentCenterX, newContact.y + newContact.contentHeight * 1.5;

local unknownContact = widget.newButton
{
	id = "unknownContact",
    left = 100,
    top = 200,
    label = "Edit Unknown Contact",
    font = native.systemFontBold,
    fontSize = 18,
    width = 300, height = 50,
    onRelease = handleButtons
}
unknownContact.x, unknownContact.y = display.contentCenterX, viewContact.y + viewContact.contentHeight * 1.5;
