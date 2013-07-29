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
	local unknownContactOptions = 
	{
		option = "unknownContact",
		-- If true then tapping/touching a contacts phone number or email will perform the default iOS action (such as call contact, show the compose email popup).
		performDefaultAction = false,
		-- Specifies whether buttons appear to let the user perform actions such as sharing the contact, initiating a FaceTime call, or sending a text message.
		allowsActions = true,
		-- The person record is only added to the address book database if allowsAdding is true and the user taps the “Add to Existing Contact” or “Create New Contact” button.
		allowsAdding = true,
		-- Provides a value that is displayed instead of the first and last name.
		alternateName = "Corona Labs",
		-- Text displayed below alternateName.
		message = "Software Company",

		-- (Required) table containing key/value pairs to ammend to a contact or to create a new contact with.
		data = 
		{
			organization = "Corona Labs", 
			workEmail = "support@coronalabs.com",
		},
		-- The onComplete listener
		listener = nil,
	}
	
	-- Create some information text
	local appendText = display.newText( group, "Append Info To Contact", 0, 50, native.systemFontBold, 16 )
	appendText.x = display.contentCenterX
	appendText:setTextColor( 0 )
	
	-- Create a text box that will be used to display the information retrieved from the onComplete listener below
	local textBox = native.newTextBox( 20, 100, 280, 240 )
	textBox.isEditable = false
	textBox.text = "Alternate Name: " .. unknownContactOptions.alternateName .. "\nMessage: " .. unknownContactOptions.message .. "\nOrganization: " .. unknownContactOptions.data.organization .. "\nWork Email: " .. unknownContactOptions.data.workEmail
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
	
	-- Set the listener
	unknownContactOptions.listener = onComplete
	
	-- Create a widget button that will display the contact list upon release
	local displayPicker = widget.newButton
	{
		id = "Show Picker",
	    left = 100,
	    top = 360,
	    label = "Add/Append To Contact",
	    font = native.systemFontBold,
	    fontSize = 18,
	    width = 240, height = 50,
	    onRelease = function() textBox.text = ""; native.showPopup( "addressbook", unknownContactOptions ) end
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
	
	storyboard.removeAll()
end

scene:addEventListener( "exitScene" )

return scene
