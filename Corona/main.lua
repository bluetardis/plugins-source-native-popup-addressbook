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

-- Require the widget library
local widget = require( "widget" )
local storyboard = require( "storyboard" )

-- If we are on the simulator, show a warning that this plugin is only supported on device
if "simulator" == system.getInfo( "environment" ) then
	native.showAlert( "Build for device", "This plugin is not supported on the Corona Simulator, please build for an iOS device or Xcode simulator", { "OK" } )
end

-- Set the status bar to show the default iOS status bar
display.setStatusBar( display.HiddenStatusBar )

-- Create a gradient for the top-half of the toolbar
local toolbarGradient = 
{
    type = "gradient",
    color1 = { 0.65, 0.70, 0.77, 1 }, 
    color2 = { 0.54, 0.61, 0.70, 1 }, 
    direction = "down", 
}

-- Create toolbar to go at the top of the screen
local titleBar = display.newRect( display.contentCenterX, 22, display.contentWidth, 44 )
titleBar:setFillColor( toolbarGradient )

-- Create embossed text to go on the toolbar
local titleText = display.newEmbossedText( "Address Book Demo", 160, titleBar.y, native.systemFontBold, 20 )


-- Create the tabBar's buttons
local tabButtons = 
{
    {
        width = 32, 
        height = 32,
        defaultFile = "assets/tabIcon.png",
        overFile = "assets/tabIcon-down.png",
        label = "List",
        labelColor =
        {
            default = { 0, 0, 0, 1 },
            over = { 0.2, 0.2, 1 },
        },
        font = native.systemFontBold,
        size = 10,
        onPress = function() storyboard.gotoScene( "listContacts" ) end,
        selected = true
    },
	{
        width = 32, 
        height = 32,
        defaultFile = "assets/tabIcon.png",
        overFile = "assets/tabIcon-down.png",
        label = "Create",
        labelColor =
        {
            default = { 0, 0, 0, 1 },
            over = { 0.2, 0.2, 1 },
        },
        font = native.systemFontBold,
        size = 10,
        onPress = function() storyboard.gotoScene( "createContact" ) end,
        selected = false
    },
	{
        width = 32, 
        height = 32,
        defaultFile = "assets/tabIcon.png",
        overFile = "assets/tabIcon-down.png",
        label = "Edit",
        labelColor =
        {
            default = { 0, 0, 0, 1 },
            over = { 0.2, 0.2, 1 },
        },
        font = native.systemFontBold,
        size = 10,
        onPress = function() storyboard.gotoScene( "editContact" ) end,
        selected = false
    },
	{
        width = 32, 
        height = 32,
        defaultFile = "assets/tabIcon.png",
        overFile = "assets/tabIcon-down.png",
        label = "Add/Append",
        labelColor =
        {
            default = { 0, 0, 0, 1 },
            over = { 0.2, 0.2, 1 },
        },
        font = native.systemFontBold,
        size = 10,
        onPress = function() storyboard.gotoScene( "addToOrAppendContact" ) end,
        selected = false
    }
}


-- Create a tabBar
local tabBar = widget.newTabBar
{
    left = 0,
    top = display.contentHeight - 52,
    width = display.contentWidth,
    buttons = tabButtons,
}

-- Start at the contact listing screen
storyboard.gotoScene( "listContacts" )
