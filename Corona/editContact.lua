--*********************************************************************************************
-- ====================================================================
-- Corona SDK "Address Book" Sample Code
-- ====================================================================
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

-- Require the storyboard and widget libraries
local storyboard = require( "storyboard" )
local widget = require( "widget" )

-- Create a new scene
local scene = storyboard.newScene()

-- Our create scene function
function scene:createScene( event )
	local group = self.view
	
	-- Display a background
	local background = display.newImage( group, "assets/background.png", true )
	background.x = display.contentCenterX
	background.y = display.contentCenterY
end

-- Add the create scene listener
scene:addEventListener( "createScene" )

-- Our enter scene function
function scene:enterScene( event )
	local group = self.view
	
	-- Create a table which will store which information we wish to use with the contact list
	local viewContactOptions = 
	{
		option = "viewContact",
		-- If true then tapping/touching a contacts phone number or email will perform the default iOS action (such as call contact, show the compose email popup).
		performDefaultAction = true,
		-- Specifies whether the user can edit the person’s information.
		isEditable = true,
		-- (Required) Name of the contact you wish to view.
		name = "",
		-- Items to show in the detail view section of a contact.
		filter = 
		{
			"phone", "email", "address",
			"birthday", "relatedNames",
			"socialProfiles", "instantMessagingProfiles",
		},
		-- The onComplete listener
		listener = nil,
	}
	
	-- Create some information text
	local contactName = display.newText( group, "Enter Name Of Contact To Edit", 0, 50, native.systemFontBold, 16 )
	contactName.x = display.contentCenterX
	contactName:setTextColor( 0 )
	
	-- Our input listener for the name field
	local function onUserInput( event )
		local phase = event.phase
		
		if "editing" == phase then
			viewContactOptions.name = event.text
		elseif "submitted" == phase or "ended" == phase then
			native.setKeyboardFocus( nil )
		end
	end
	
	-- The namefield
	local nameField = native.newTextField( 20, 80, 280, 30 )
	nameField.x = display.contentCenterX
	nameField.placeholder = "Name of the contact to edit"
	nameField:addEventListener( "userInput", onUserInput )
	nameField:setReturnKey( "done" )
	self.nameField = nameField
	
	-- Create a text box that will be used to display the information retrieved from the onComplete listener below
	local textBox = native.newTextBox( 20, 120, 280, 220 )
	textBox.isEditable = false
	textBox.size = 16
	self.textBox = textBox
	
	-- Callback function which executes upon dismissal of the contact view controller 
	local function onComplete( event )		
		print( "event.name:", event.name );
		print( "event.type:", event.type );

		-- event.data is either a table or nil depending on the option chosen
		print ( "event.data:", event.data );

		-- If there is event.data print it's key/value pairs
		if event.data then
			print( "event.data: {" );

			for k, v in pairs( event.data ) do
				local kk, vv = k, v
				
				if type( v ) == "table" then
					vv = "table"
				end
				
				textBox.text = textBox.text .. " " .. kk .. ":  " .. vv .. "\n"
				print( k , ":" , v );
			end	

			print( "}" );
		end		
	end
	
	
	local function handleButtonPress( event )
		if string.len( viewContactOptions.name ) <= 0 then
			native.showAlert( "Cannot view contact with no name", "Please enter the name of the contact you wish to view in the box at the top of the screen", { "Ok" } )
		else
			textBox.text = ""
			native.showPopup( "addressbook", viewContactOptions )
		end
	end
	
	-- Set the listener
	viewContactOptions.listener = onComplete
	
	-- Create a widget button that will display the contact list upon release
	local displayPicker = widget.newButton
	{
		id = "Show Picker",
	    left = 100,
	    top = 360,
	    label = "Edit Contact",
	    font = native.systemFontBold,
	    fontSize = 18,
	    width = 220, height = 50,
	    onRelease = handleButtonPress,
	}
	displayPicker.x = display.contentCenterX
	group:insert( displayPicker )
end

-- Add the enter scene listener
scene:addEventListener( "enterScene" )


-- Our exit scene function
function scene:exitScene( event )
	display.remove( self.textBox )
	self.textBox = nil
	
	display.remove( self.nameField )
	self.nameField = nil
	
	storyboard.removeAll()
end

scene:addEventListener( "exitScene" )

return scene
