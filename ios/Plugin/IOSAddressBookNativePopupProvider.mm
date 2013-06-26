// ----------------------------------------------------------------------------
// 
// IOSAddressBookNativePopupProvider.mm
// Copyright (c) 2013 Corona Labs Inc. All rights reserved.
// 
// ----------------------------------------------------------------------------

#include "IOSAddressBookNativePopupProvider.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Accounts/Accounts.h>
#import <AddressBook/AddressBook.h>
#import <AddressBookUI/AddressBookUI.h>

#import "CoronaRuntime.h"
#include "CoronaAssert.h"
#include "CoronaEvent.h"
#include "CoronaLua.h"
#include "CoronaLibrary.h"
#include "IOSAddressBookNativePopupProvider.h"

// ----------------------------------------------------------------------------

// Set up our delegate
@interface CoronaAddressBookDelegate : NSObject
<
	ABPeoplePickerNavigationControllerDelegate,
	ABPersonViewControllerDelegate,
	ABNewPersonViewControllerDelegate,
	ABUnknownPersonViewControllerDelegate
>

// Contact properties
@property (nonatomic) bool shouldHideDetails;
@property (nonatomic) bool shouldPerformDefaultAction;
@property (nonatomic) bool shouldAllowContactEditing;
@property (nonatomic) bool shouldAllowActions;
@property (nonatomic) bool shouldAllowAdding;

// Arrays
@property (nonatomic, retain) NSMutableArray *contactDisplayFilters;

// Misc
@property (nonatomic, retain) NSString *chosenAddressBookOption;
@property (nonatomic, assign) UIViewController *currentViewController;
@property (nonatomic) bool hasChosenPerson;

// Lua
@property (nonatomic, assign) lua_State *luaState; // Pointer to the current lua state
@property (nonatomic) int callbackRef; // Reference to store our onComplete function

@end

@class CoronaAddressBookDelegate;

// ----------------------------------------------------------------------------

class IOSAddressBookNativePopupProvider
{
	public:
		typedef IOSAddressBookNativePopupProvider Self;

	public:
		static int Open( lua_State *L );
		static int Finalizer( lua_State *L );
		static Self *ToLibrary( lua_State *L );

	protected:
		IOSAddressBookNativePopupProvider();
		bool Initialize( void *platformContext );
		
	public:
		UIViewController* GetAppViewController() const { return fAppViewController; }

	public:
		static int canShowPopup( lua_State *L );
		static int showPopup( lua_State *L );

	private:
		UIViewController *fAppViewController;
};

// ----------------------------------------------------------------------------


namespace Corona
{

// ----------------------------------------------------------------------------

class IOSAddressBookNativePopupProvider
{
	public:
		typedef IOSAddressBookNativePopupProvider Self;

	public:
		static int Open( lua_State *L );
		static int Finalizer( lua_State *L );
		static Self *ToLibrary( lua_State *L );

	protected:
		IOSAddressBookNativePopupProvider();
		bool Initialize( void *platformContext );

	public:
		UIViewController* GetAppViewController() const { return fAppViewController; }
	
	public:
		static int canShowPopup( lua_State *L );
		static int showPopup( lua_State *L );

	private:
		UIViewController *fAppViewController;
};

// ----------------------------------------------------------------------------

static const char kPopupName[] = "addressBook";
static const char kMetatableName[] = __FILE__; // Globally unique value


int
IOSAddressBookNativePopupProvider::Open( lua_State *L )
{
	CoronaLuaInitializeGCMetatable( L, kMetatableName, Finalizer );
	void *platformContext = CoronaLuaGetContext( L );

	const char *name = lua_tostring( L, 1 ); CORONA_ASSERT( 0 == strcmp( kPopupName, name ) );
	int result = CoronaLibraryProviderNew( L, "native.popup", name, "com.coronalabs" );

	if ( result > 0 )
	{
		int libIndex = lua_gettop( L );

		Self *library = new Self;

		if ( library->Initialize( platformContext ) )
		{
			static const luaL_Reg kFunctions[] =
			{
				{ "canShowPopup", canShowPopup },
				{ "showPopup", showPopup },

				{ NULL, NULL }
			};

			// Register functions as closures, giving each access to the
			// 'library' instance via ToLibrary()
			{
				lua_pushvalue( L, libIndex ); // push library
				CoronaLuaPushUserdata( L, library, kMetatableName ); // push library ptr
				luaL_openlib( L, NULL, kFunctions, 1 );
				lua_pop( L, 1 ); // pop library
			}
		}
	}

	return result;
}

int
IOSAddressBookNativePopupProvider::Finalizer( lua_State *L )
{
	Self *library = (Self *)CoronaLuaToUserdata( L, 1 );
	delete library;
	return 0;
}

IOSAddressBookNativePopupProvider::Self *
IOSAddressBookNativePopupProvider::ToLibrary( lua_State *L )
{
	// library is pushed as part of the closure
	Self *library = (Self *)CoronaLuaToUserdata( L, lua_upvalueindex( 1 ) );
	return library;
}

// ----------------------------------------------------------------------------

IOSAddressBookNativePopupProvider::IOSAddressBookNativePopupProvider()
:	fAppViewController( nil )
{
}

bool
IOSAddressBookNativePopupProvider::Initialize( void *platformContext )
{
	bool result = ( ! fAppViewController );

	if ( result )
	{
		id<CoronaRuntime> runtime = (id<CoronaRuntime>)platformContext;
		fAppViewController = runtime.appViewController; // TODO: Should we retain?
	}

	return result;
}


// Constants
static const char kOptionPickContact[] = "pickContact";
static const char kOptionViewContact[] = "viewContact";
static const char kOptionNewContact[] = "newContact";
static const char kOptionUnknownContact[] = "unknownContact";


// Retrieve boolean value from lua
static int
luaRetrieveBool( lua_State *L, int index, const char *name, const char *chosenAddressBookOption )
{
	bool result = false;

	// Get field
	if ( ! lua_isnoneornil( L, index ) && lua_istable( L, index ) )
	{
		// Options table exists, retrieve name key
		lua_getfield( L, index, name );
	}
	// If the details table exists
	if ( lua_isboolean( L, -1 ) )
	{
		// Retrieve the bool
		result = lua_toboolean( L, -1 );
        
		lua_pop( L, 1 );
	}
	// If the value isn't a bool, and it wasn't ommited, throw an error.
	else if ( ! lua_isnoneornil( L, -1 ) && lua_istable( L, index ) && ! lua_isboolean( L, -1 ) )
	{
		luaL_error( L, "'%s' passed to %s must be a boolean value", name, chosenAddressBookOption );
	}

	return result;
}

// Retrieve string from lua
static const char *
luaRetrieveString( lua_State *L, int index, const char *name, const char *chosenAddressBookOption, const char *tableKey = NULL, int tableKeyIndex = NULL )
{
	const char *result = NULL;

	// Get table if specified
	if ( tableKey && tableKeyIndex )
	{
		// If the options table exists
		if ( ! lua_isnoneornil( L, tableKeyIndex ) && lua_istable( L, tableKeyIndex ) )
		{
			// Options table exists, retrieve name key
			lua_getfield( L, tableKeyIndex, tableKey );
		}
		// If the options.data field doesn't exist or or isn't a table throw an error.
		if ( ! lua_isnoneornil( L, -1 ) && lua_istable( L, tableKeyIndex ) && ! lua_istable( L, -1 ) )
		{
			luaL_error( L, "'%s' data must be a table containing key/value pairs", chosenAddressBookOption );
		}
	}

	// Get field
	if ( ! lua_isnoneornil( L, index ) )
	{
		// Options table exists, retrieve name key
		lua_getfield( L, index, name );
	}

	// If the details table exists
	if ( lua_istable( L, 2 ) && lua_isstring( L, -1 ) )
	{
		// Retrieve the string
		result = lua_tostring( L, -1 );

		lua_pop( L, 1 );
	}
	// If the value isn't a string, and it wasn't ommited, throw an error.
	else if ( ! lua_isnoneornil( L, -1 ) && ! lua_isstring( L, -1 ) )
	{
		luaL_error( L, "'%s' passed to %s options table must be a string value", name, chosenAddressBookOption );
	}

	return result;
}


// Get options table passed from lua
static int
getContactOptions( lua_State *L, CoronaAddressBookDelegate *delegate, const char *viewType, const char *chosenAddressBookOption )
{
	// Only get the boolean values that we will be using for the chosen contact view

	// Pick contact
	if ( 0 == strcmp( kOptionPickContact, viewType ) )
	{
		// Get hideDetails bool from lua, then set it
		delegate.shouldHideDetails = luaRetrieveBool( L, 2, "hideDetails", chosenAddressBookOption );
		// Get performDefaultAction bool from lua, then set it
		delegate.shouldPerformDefaultAction = luaRetrieveBool( L, 2, "performDefaultAction", chosenAddressBookOption );
	}
	// View contact
	else if ( 0 == strcmp( kOptionViewContact, viewType ) )
	{
		// Get performDefaultAction bool from lua, then set it
		delegate.shouldPerformDefaultAction = luaRetrieveBool( L, 2, "performDefaultAction", chosenAddressBookOption );
		// Get isEditable bool from lua, then set it
		delegate.shouldAllowContactEditing = luaRetrieveBool( L, 2, "isEditable", chosenAddressBookOption );
	}
	// Unknown contact
	else if ( 0 == strcmp( kOptionUnknownContact, viewType ) )
	{
		// Get performDefaultAction bool from lua, then set it
		delegate.shouldPerformDefaultAction = luaRetrieveBool( L, 2, "performDefaultAction", chosenAddressBookOption);
		// Get shouldAllowActions bool from lua, then set it
		delegate.shouldAllowActions = luaRetrieveBool( L, 2, "allowsActions", chosenAddressBookOption );
		// Get shouldAllowAdding bool from lua, then set it
		delegate.shouldAllowAdding = luaRetrieveBool( L, 2, "allowsAdding", chosenAddressBookOption );
	}
    
	return 0;
}


// Get "filter" table passed from lua
static int
getContactFilters( lua_State *L, CoronaAddressBookDelegate *delegate, const char *chosenAddressBookOption )
{
	// Get filter array (if it is a table and is not ommitted or nil)
	if ( ! lua_isnoneornil( L, 2 ) && lua_istable( L, 2 ) )
	{
		// Options table exists, retrieve name key
		lua_getfield( L, 2, "filter" );
	}

	// If the filter table exists
	if ( ! lua_isnoneornil( L, -1 ) && lua_istable( L, -1 ) )
	{
		// Get the number of defined filters from lua
		int amountOfFiltersDefined = luaL_getn( L, -1 );

		// Loop through the filter array
		for ( int i = 1; i <= amountOfFiltersDefined; ++i )
		{
			// Get the tables first value
			lua_rawgeti( L, -1, i );
            
			// Assign the value to the display filters array, we pass -1 so we match C/C++'s convention of starting arrays at 0
			NSString *currentFilter = [NSString stringWithUTF8String:lua_tostring( L, -1 )];
            
			// Add the filter to the contactDisplayFilters array
			[delegate.contactDisplayFilters addObject:currentFilter];

			// Pop the current filter
			lua_pop( L, 1 );
		}
	}

	// If there is an options table & there is filter passed and the filter defined isn't a table
	if ( lua_istable( L, 2 ) && ! lua_istable( L, -1 ) && ! lua_isnoneornil( L, -1 ) )
	{
		luaL_error( L, "'Filter' passed to %s options must be a table, and must contain strings identifiying which properties you wish to display", chosenAddressBookOption );
	}
		
	// Pop the options.filter table
	lua_pop( L, 1 );

	return 0;
}


// Helper function for setting contact details. Used in newContact and unknownContact
static int
setContactDetails( lua_State *L, ABRecordRef person, const char *chosenAddressBookOption )
{
	bool result = false;
	CFErrorRef error = NULL;

	// Retrieve the pre-filled contact fields from lua (if any)
	const char *contactFirstName = luaRetrieveString( L, -1, "firstName", chosenAddressBookOption, "data", 2 );
	const char *contactLastName = luaRetrieveString( L, -1, "lastName", chosenAddressBookOption, "data", 2 );
	const char *contactOrganization = luaRetrieveString( L, -1, "organization", chosenAddressBookOption, "data", 2 );
	const char *contactHomePhoneNumber = luaRetrieveString( L, -1, "homePhone", chosenAddressBookOption, "data", 2 );
	const char *contactWorkPhoneNumber = luaRetrieveString( L, -1, "workPhone", chosenAddressBookOption, "data", 2 );
	const char *contactHomeEmailAddress = luaRetrieveString( L, -1, "homeEmail", chosenAddressBookOption, "data", 2 );
	const char *contactWorkEmailAddress = luaRetrieveString( L, -1, "workEmail", chosenAddressBookOption, "data", 2 );
	//Pop the options.data table
	lua_pop(L, 1);

	// Create multi value references
	ABMutableMultiValueRef phoneNumbers = ABMultiValueCreateMutable(kABMultiStringPropertyType);
	ABMutableMultiValueRef emailAddresses = ABMultiValueCreateMutable(kABMultiStringPropertyType);

	// If there is a first name - (We don't use this in the unknownContact option)
	if ( contactFirstName && ! ( 0 == strcmp( kOptionUnknownContact, chosenAddressBookOption ) ) )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactFirstName];
		ABRecordSetValue(person, kABPersonFirstNameProperty, value, &error);
		result = true;
	}

	// If there is a last name - (We don't use this in the unknownContact option)
	if ( contactLastName && ! ( 0 == strcmp( kOptionUnknownContact, chosenAddressBookOption ) ) )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactLastName];
		ABRecordSetValue(person, kABPersonLastNameProperty, value, &error);
		result = true;
	}

	// If there is a organization
	if ( contactOrganization )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactOrganization];
		ABRecordSetValue(person, kABPersonOrganizationProperty, value, &error);
		result = true;
	}

	// If there is a home phone number
	if ( contactHomePhoneNumber )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactHomePhoneNumber];
		ABMultiValueAddValueAndLabel(phoneNumbers, value, kABHomeLabel, NULL);
		result = true;
	}

	// If there is a work phone number
	if ( contactWorkPhoneNumber )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactWorkPhoneNumber];
		ABMultiValueAddValueAndLabel(phoneNumbers, value, kABWorkLabel, NULL);
		result = true;
	}

	// If there is a home email address
	if ( contactHomeEmailAddress )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactHomeEmailAddress];
		ABMultiValueAddValueAndLabel(emailAddresses, value, kABHomeLabel, NULL);
		result = true;
	}

	// If there is a work email address
	if ( contactWorkEmailAddress )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactWorkEmailAddress];
		ABMultiValueAddValueAndLabel(emailAddresses, value, kABWorkLabel, NULL);
		result = true;
	}

	// If the passed items contain at least one phone number then set the values
	if ( (contactHomePhoneNumber) || (contactWorkPhoneNumber) )
	{
		ABRecordSetValue(person, kABPersonPhoneProperty, phoneNumbers, &error);
	}
	// If the passed items contain at least one email address then set the values
	if ( (contactWorkEmailAddress) || (contactHomeEmailAddress) )
	{
		ABRecordSetValue(person, kABPersonEmailProperty, emailAddresses, &error);
	}


	// Error
	if ( error )
	{
		printf( "Adding details failed" );
		result = false;
	}

	// Cleanup
	CFRelease( phoneNumbers );
	CFRelease( emailAddresses );

	return result;
}


// Show contact picker
static int
pickContact( lua_State *L, UIViewController *runtimeViewController, CoronaAddressBookDelegate *delegate )
{
	// Initialize the picker controller
	ABPeoplePickerNavigationController *picker = [[ABPeoplePickerNavigationController alloc] init];
	picker.peoplePickerDelegate = delegate;
	
	// If the user hasn't specified to hide the detail view of contact info
	if ( false == delegate.shouldHideDetails )
	{
		// Array to hold which items to display
		NSMutableArray *displayedItems = [[NSMutableArray alloc] init];	

		// Items to display
		NSNumber *propertiesPersonPhone = [[NSNumber alloc] initWithInt:(int)kABPersonPhoneProperty];
		NSNumber *propertiesPersonEmail = [[NSNumber alloc] initWithInt:(int)kABPersonEmailProperty];
		NSNumber *propertiesPersonBirthday = [[NSNumber alloc] initWithInt:(int)kABPersonBirthdayProperty];

		// Check if a filter exists and matches the required name, if it does, display it
		int numOfFilters = [delegate.contactDisplayFilters count];

		for ( int i = 0; i < numOfFilters; ++i )
		{
			const char *currentFilter = [[NSString stringWithFormat:@"%@",[delegate.contactDisplayFilters objectAtIndex:i]] UTF8String];

			if ( 0 == strcmp( "phone", currentFilter ) )
			{
				[displayedItems addObject:propertiesPersonPhone];
			}
			else if ( 0 == strcmp( "email", currentFilter ) )
			{
				[displayedItems addObject:propertiesPersonEmail];
			}
			else if ( 0 == strcmp( "birthday", currentFilter ) )
			{
				[displayedItems addObject:propertiesPersonBirthday];
			}
		}

		// Set the pickers displayed properties to the displayedItems array.
		picker.displayedProperties = displayedItems;

		// Cleanup
		[propertiesPersonPhone release];
		[propertiesPersonEmail release];
		[propertiesPersonBirthday release];
		[displayedItems release];
	}
	
	// Present the view controller
	[runtimeViewController presentModalViewController:picker animated:YES];

	// Cleanup
	[picker release];

	return 0;
}


// Show view contact
static int
viewContact( lua_State *L, UIViewController *runtimeViewController, CoronaAddressBookDelegate *delegate )
{
	const char *requestedPersonName = NULL;

	// Get the name key
	if ( ! lua_isnoneornil( L, 2 ) )
	{
		// Options table exists, retrieve name key
		lua_getfield( L, 2, "name" );

		// If the key has been specified, is not nil and it is a string then check it.
		if ( ! lua_isnoneornil( L, -1 ) && lua_isstring( L, -1 ) )
		{
			// Enforce string
			luaL_checktype( L, -1, LUA_TSTRING );

			// Check the string
			requestedPersonName = luaL_checkstring( L, -1 );
		}
		// They key was omitted, throw error
		else
		{
			luaL_error( L, "%s options table 'name' parameter (String) was not specified", "viewContact" );
		}
	}
	// The options table doesn't exist, throw error
	else
	{
		luaL_error( L, "%s requires an options table containing at the very least a 'name' parameter (String) of the contact you wish to view", "viewContact" );
	}


	// If there is a requested person name
	if ( requestedPersonName )
	{
		//Persons name to search for
		CFStringRef searchForName = (CFStringRef)[NSString stringWithUTF8String:requestedPersonName];

		// Pop the requested name
		lua_pop( L, 1 );

		//Message to show if contact not found
		NSString *contactNotFound = [NSString stringWithFormat:@"%@ %@ %@", @"Could not find '", searchForName, @"' in the Contacts application"];
		
		// Fetch the address book
		ABAddressBookRef addressBook = ABAddressBookCreate();
		// Search for the person specified by the user in the address book
		NSArray *people = (NSArray *)ABAddressBookCopyPeopleWithName(addressBook, searchForName);

		// Display the passed contact information if found in the address book
		if ( nil != people && 0 != people.count )
		{
			ABRecordRef person = (ABRecordRef)[people objectAtIndex:0];
			ABPersonViewController *picker = [[[ABPersonViewController alloc] init] autorelease];

			// We need to add in a cancel button so the user can dismiss the picker
			UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Cancel",nil) style:UIBarButtonItemStylePlain target:delegate action:@selector(cancelledFromPicker:)];
			picker.navigationItem.backBarButtonItem = cancelButton;
			[cancelButton release];

			picker.personViewDelegate = delegate;
			picker.displayedPerson = person;

			// Array to hold which items to display
			NSMutableArray *displayedItems = [[NSMutableArray alloc] init];

			// Items to display
			NSNumber *propertiesPersonPhone = [[NSNumber alloc] initWithInt:(int)kABPersonPhoneProperty];
			NSNumber *propertiesPersonEmail = [[NSNumber alloc] initWithInt:(int)kABPersonEmailProperty];
			NSNumber *propertiesPersonBirthday = [[NSNumber alloc] initWithInt:(int)kABPersonBirthdayProperty];

			// Check if a filter exists and matches the required name, if it does, display it
			int numOfFilters = [delegate.contactDisplayFilters count];

			for ( int i = 0; i < numOfFilters; ++i )
			{
				const char *currentFilter = [[NSString stringWithFormat:@"%@", [delegate.contactDisplayFilters objectAtIndex:i]] UTF8String];

				if ( 0 == strcmp( "phone", currentFilter ) )
				{
					[displayedItems addObject:propertiesPersonPhone];
				}
				else if ( 0 == strcmp( "email", currentFilter ) )
				{
					[displayedItems addObject:propertiesPersonEmail];
				}
				else if ( 0 == strcmp( "birthday", currentFilter ) )
				{
					[displayedItems addObject:propertiesPersonBirthday];
				}
			}

			// Set the pickers displayed properties to the displayedItems array.
			picker.displayedProperties = displayedItems;

			// Allow users to edit the person’s information (if user allows it)
			picker.allowsEditing = delegate.shouldAllowContactEditing;

			UINavigationController *contactNavController = [[UINavigationController alloc] initWithRootViewController:picker];
			delegate.currentViewController = contactNavController;
			[runtimeViewController presentModalViewController:contactNavController animated:YES];

			// Cleanup
			[contactNavController release];
			[propertiesPersonPhone release];
			[propertiesPersonEmail release];
			[propertiesPersonBirthday release];
			[displayedItems release];
		}
		// Specified Contact was not found, throw alert ( This will probably need removing, and instead fire a "failed to find contact" callback or similar
		else
		{
			// Show an alert if user chosen contact is not in the address book
			UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Contact Not Found" message:contactNotFound delegate:nil cancelButtonTitle:@"Ok" otherButtonTitles:nil];
			[alert performSelector:@selector(show) withObject:nil afterDelay:0.0];

			// Cleanup
			[alert release];
		}

		// Cleanup
		[people release];
		CFRelease(addressBook);
	}
	
	return 0;
}


// New contact ( not finished and not happy with the implementation yet, it works, but ignore for now )
static int
newContact( lua_State *L, UIViewController *runtimeViewController, CoronaAddressBookDelegate *delegate, const char *chosenAddressBookOption )
{	
	// Create a new person record
	ABRecordRef newPerson = ABPersonCreate();

	// Set the new contact's details from the "data" table passed from lua
	bool didAddContactDetails = setContactDetails( L, newPerson, chosenAddressBookOption );

	// If there are details to display
	if ( didAddContactDetails )
	{
		// Initialize the picker controller
		ABNewPersonViewController *picker = [[ABNewPersonViewController alloc] init];

		// Set the displayed person
		[picker setDisplayedPerson:newPerson];
		picker.newPersonViewDelegate = delegate;

		UINavigationController *contactNavController = [[UINavigationController alloc] initWithRootViewController:picker];
		[runtimeViewController presentModalViewController:contactNavController animated:YES];

		// Cleanup
		[picker release];
		[contactNavController release];
	}
	else
	{
		luaL_error( L, "%s requires a options table and data subtable to exist and the data table to contain at least one key/value pair", chosenAddressBookOption );
	}

	// Cleanup
	CFRelease( newPerson );

	return 0;
}


// Unkown contact
static int
unknownContact( lua_State *L, UIViewController *runtimeViewController, CoronaAddressBookDelegate *delegate, const char *chosenAddressBookOption )
{
	// Retrieve the alternateName & message passed by lua (if any)
	const char *alternateName = luaRetrieveString( L, -1, "alternateName", chosenAddressBookOption );
	const char *message = luaRetrieveString( L, -1, "message", chosenAddressBookOption );

	// Create a new person record
	ABRecordRef newPerson = ABPersonCreate();

	// Set the new contact's details from the "data" table passed from lua
	bool didAddContactDetails = setContactDetails( L, newPerson, chosenAddressBookOption );

	// If there are details to display
	if ( didAddContactDetails )
	{
		ABUnknownPersonViewController *picker = [[ABUnknownPersonViewController alloc] init];
		picker.unknownPersonViewDelegate = delegate;
		picker.displayedPerson = newPerson;
		picker.allowsAddingToAddressBook = delegate.shouldAllowAdding;
		picker.allowsActions = delegate.shouldAllowActions;
			
		// If there is an alternate name
		if ( alternateName )
		{
			NSString *value = [NSString stringWithUTF8String:alternateName];
			picker.alternateName = value;
			picker.title = value;
		}
			
		// If there is a message
		if  ( message )
		{
			NSString *value = [NSString stringWithUTF8String:message];
			picker.message = value;
		}

		// We need to add in a cancel button so the user can dismiss the picker
		UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Cancel",nil) style:UIBarButtonItemStylePlain target:delegate action:@selector(cancelledFromPicker:)];
		picker.navigationItem.leftBarButtonItem = cancelButton;
		[cancelButton release];

		UINavigationController *contactNavController = [[UINavigationController alloc] initWithRootViewController:picker];
		delegate.currentViewController = contactNavController;
		[runtimeViewController presentModalViewController:contactNavController animated:YES];

		// Cleanup
		[picker release];
		[contactNavController release];
	}
	else
	{
		luaL_error( L, "%s requires a options table and data subtable to exist and the data table to contain at least one key/value pair", chosenAddressBookOption );
	}

	// Cleanup
	CFRelease( newPerson );

	return 0;
}

// canShowPopup
int
IOSAddressBookNativePopupProvider::canShowPopup( lua_State *L )
{
	bool isAvailable = false;
	const char *popUpName = lua_tostring( L, 1 );
	
	if ( 0 == strcmp( kPopupName, popUpName ) )
	{
		isAvailable = true;
	}
	
	lua_pushboolean( L, isAvailable );

	return 1;
}

// showPopup
int
IOSAddressBookNativePopupProvider::showPopup( lua_State *L )
{
	using namespace Corona;

	Self *context = ToLibrary( L );
	
	// The result
	int result = 0;
	
	// Retrieve the popup name
	const char *popUpName =lua_tostring( L, 1 );

	if ( context && 0 == strcmp( "addressBook", popUpName ) )
	{
		Self& library = * context;
		
		// Create an instance of our delegate
		CoronaAddressBookDelegate *delegate = [[CoronaAddressBookDelegate alloc] init];
		
		// Assign our runtime view controller
		UIViewController *appViewController = library.GetAppViewController();
		
		// Assign the lua state so we can access it from within the delegate
		delegate.luaState = L;

		// Set the callback reference to 0
		delegate.callbackRef = 0;
		
		// Set reference to onComplete function
		if ( lua_istable( L, 2 ) )
		{
			// Get listener key
			lua_getfield( L, 2, "listener" );
			
			// Set the delegates callbackRef to reference the onComplete function (if it exists)
			if ( lua_isfunction( L, -1 ) )
			{
				delegate.callbackRef = luaL_ref( L, LUA_REGISTRYINDEX );
			}
		}
		
		// Initialize the display filters array
		delegate.contactDisplayFilters = [[NSMutableArray alloc] init];

		// Get the option key
		lua_getfield(L, 2, "option" );

		// Check the "name" parameter from lua
		const char *chosenAddressBookOption = lua_tostring( L, -1 );

		// If there was no option key passed
		if ( NULL == chosenAddressBookOption )
		{
			luaL_error( L, "Unrecognized 'option' parameter passed to showPopup()", chosenAddressBookOption );
			return 0;
		}

		// Assign the chosen option to the delegate ( so we can reference it where needed )
		delegate.chosenAddressBookOption = [NSString stringWithUTF8String:chosenAddressBookOption];

		// Pick Contact
		if ( 0 == strcmp( kOptionPickContact, chosenAddressBookOption )  )
		{
			// Get the passed options from lua
			getContactOptions( L, delegate, kOptionPickContact, chosenAddressBookOption );

			// Get the contact filters from lua
			getContactFilters( L, delegate, chosenAddressBookOption );

			// Show the picker
			result = pickContact( L, appViewController, delegate );
		}
		// View Contact
		else if ( 0 == strcmp( kOptionViewContact, chosenAddressBookOption ) )
		{
			// Get the passed options from lua
			getContactOptions( L, delegate, kOptionViewContact, chosenAddressBookOption );

			// Get the contact filters from lua
			getContactFilters( L, delegate, chosenAddressBookOption );

			// Show the picker
			result = viewContact( L, appViewController, delegate );
		}
		// New Contact
		else if ( 0 == strcmp( kOptionNewContact, chosenAddressBookOption ) )
		{
			// Show the picker
			result = newContact( L, appViewController, delegate, chosenAddressBookOption );
		}
		// Unkown Contact
		else if ( 0 == strcmp( kOptionUnknownContact, chosenAddressBookOption ) )
		{
			// Get the passed options from lua
			getContactOptions( L, delegate, kOptionUnknownContact, chosenAddressBookOption );

			// Show the picker
			result = unknownContact( L, appViewController, delegate, chosenAddressBookOption );
		}
		else
		{
			luaL_error( L, "Unrecognized 'option' parameter passed to showPopup()", chosenAddressBookOption );
		}

		// Cleanup
		[delegate.contactDisplayFilters release];
	}

	return result;
}


// ----------------------------------------------------------------------------

} // namespace Corona

// ----------------------------------------------------------------------------



// Implementation
@implementation CoronaAddressBookDelegate

// Synthesize properties
@synthesize shouldHideDetails, shouldPerformDefaultAction, shouldAllowContactEditing;
@synthesize shouldAllowActions, shouldAllowAdding, hasChosenPerson;

// Only execute callback function if there is a reference to it ( if there isn't it means no callback function was passed )
- (int) dispatchAddressBookEvent:(ABRecordRef)person :(const char *)eventType
{
	// If there is a callback to execute
	if ( 0 != self.callbackRef )
	{
		// Push the onComplete function onto the stack
		lua_rawgeti( self.luaState, LUA_REGISTRYINDEX, self.callbackRef );

		// event table
		lua_newtable( self.luaState );

		if ( nil != eventType && 0 == strcmp( "data", eventType ) )
		{
			printf( "setting data table " );
			
			// event.data table
			lua_newtable( self.luaState );

			// Create multi value references 
			ABMultiValueRef phoneNumbers = ABRecordCopyValue(person, kABPersonPhoneProperty);
			ABMultiValueRef emailAddresses = ABRecordCopyValue(person, kABPersonEmailProperty);

			// Retrieve contact details
			NSString *contactFirstName = (NSString *)ABRecordCopyValue(person, kABPersonFirstNameProperty);
			NSString *contactLastName = (NSString *)ABRecordCopyValue(person, kABPersonLastNameProperty);
			NSDate *contactBirthday = (NSDate *)(ABRecordCopyValue(person, kABPersonBirthdayProperty));
			NSString *contactEmail = nil;
			NSString *contactPhone = nil;

			// If there are any email addresses
			if ( ABMultiValueGetCount( emailAddresses ) > 0 )
			{
				contactEmail = (NSString *)ABMultiValueCopyValueAtIndex(emailAddresses, 0);
			}

			// If there are any phone numbers
			if ( ABMultiValueGetCount( phoneNumbers ) > 0 )
			{
				contactPhone = (NSString *)ABMultiValueCopyValueAtIndex(phoneNumbers, 0);
			}

			// Add key/value pairs to the event.data table
			if ( contactFirstName )
			{
				const char *firstName = [contactFirstName UTF8String];
				lua_pushstring( self.luaState, firstName ); // Value
				lua_setfield( self.luaState, -2, "firstName" ); // Key
			}

			if ( contactLastName )
			{
				const char *lastName = [contactLastName UTF8String];
				lua_pushstring( self.luaState,  lastName ); // Value
				lua_setfield( self.luaState, -2, "lastName" ); // Key
			}

			if ( contactPhone )
			{
				const char *phone = [contactPhone UTF8String];
				lua_pushstring( self.luaState, phone ); // Value
				lua_setfield( self.luaState, -2, "phone" ); // Key
			}

			if ( contactEmail )
			{
				const char *email = [contactEmail UTF8String];
				lua_pushstring( self.luaState, email ); // Value
				lua_setfield( self.luaState, -2, "email" ); // Key
			}

			if ( contactBirthday )
			{
				NSString *value = [NSDateFormatter localizedStringFromDate:contactBirthday dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterNoStyle];
				const char *birthday = [value UTF8String];

				lua_pushstring( self.luaState, birthday ); // Value
				lua_setfield( self.luaState, -2, "birthday" ); // Key
			}

			// Set event.data
			lua_setfield( self.luaState, -2, "data" );

			// Cleanup
			CFRelease( phoneNumbers );
			CFRelease( emailAddresses );
		}

		// Set table events ( event.* )

		// Set event.name property
		lua_pushstring( self.luaState, "contact" ); // Value ( name )
		lua_setfield( self.luaState, -2, "name" ); // Key

		// Set event.type
		const char *eventName = [self.chosenAddressBookOption UTF8String];

		lua_pushstring( self.luaState, eventName ); // Value ( function type name )
		lua_setfield( self.luaState, -2, "type" ); // Key

		// Call the onComplete function
		Corona::Lua::DoCall( self.luaState, 1, 1 );
		
		// Free the refrence
		lua_unref( self.luaState, self.callbackRef );
	}

	return 0;
}

// Custom cancel action for navigation controllers that don't offer a cancel button by default
- (void) cancelledFromPicker:(id)sender
{
	// Dismiss the current view controller
	[self.currentViewController dismissModalViewControllerAnimated:YES];

	// If the user hasn't chosen a person ( ie a direct cancel action )
	if ( false == self.hasChosenPerson )
	{
		// Dispatch cancelled event ( if one exists )
		[self dispatchAddressBookEvent:nil:nil];
	}

	// Set chosen person back to false
	self.hasChosenPerson = false;	
}

#pragma mark ABPeoplePickerNavigationControllerDelegate methods
// Displays the information of a selected person
- (BOOL)peoplePickerNavigationController:(ABPeoplePickerNavigationController *)peoplePicker shouldContinueAfterSelectingPerson:(ABRecordRef)person
{
	// If we should hide details, dismiss the picker upon selecting a contact
	if ( true == shouldHideDetails )
	{
		// Dismiss the picker
		[peoplePicker dismissModalViewControllerAnimated:YES];

		// Dispatch data event ( if one exists )
		[self dispatchAddressBookEvent:person:"data"];
	}

	// The ! is intended
	return ! shouldHideDetails;
}

// If allowed execute default actions such as dialing a phone number, when they select a contact property.
- (BOOL)peoplePickerNavigationController:(ABPeoplePickerNavigationController *)peoplePicker shouldContinueAfterSelectingPerson:(ABRecordRef)person
								property:(ABPropertyID)property identifier:(ABMultiValueIdentifier)identifier
{	
	return shouldPerformDefaultAction;
}

// Dismisses the people picker and shows the application when users tap Cancel.
- (void)peoplePickerNavigationControllerDidCancel:(ABPeoplePickerNavigationController *)peoplePicker
{
	// Dismiss the picker
	[peoplePicker dismissModalViewControllerAnimated:YES];

	// Dispatch cancelled event ( if one exists )
	[self dispatchAddressBookEvent:nil:nil];
}


#pragma mark ABPersonViewControllerDelegate methods
// If allowed execute default actions such as dialing a phone number, when they select a contact property.
- (BOOL)personViewController:(ABPersonViewController *)personViewController shouldPerformDefaultActionForPerson:(ABRecordRef)person
					property:(ABPropertyID)property identifier:(ABMultiValueIdentifier)identifierForValue
{
	return shouldPerformDefaultAction;
}


#pragma mark ABNewPersonViewControllerDelegate methods
// Dismisses the new-person view controller. 
- (void)newPersonViewController:(ABNewPersonViewController *)newPersonViewController didCompleteWithNewPerson:(ABRecordRef)person
{
	// Dismiss the picker
	[newPersonViewController dismissModalViewControllerAnimated:YES];

	// If user cancelled
	if ( NULL == person )
	{
		// Dispatch cancelled event ( if one exists )
		[self dispatchAddressBookEvent:nil:nil];
	}
	// If user entered contact
	else
	{
		// Dispatch data event ( if one exists )
		[self dispatchAddressBookEvent:person:"data"];
	}
}


#pragma mark ABUnknownPersonViewControllerDelegate methods
// Dismisses the picker when users are done creating a contact or adding the displayed person properties to an existing contact. 
- (void)unknownPersonViewController:(ABUnknownPersonViewController *)unknownPersonView didResolveToPerson:(ABRecordRef)person
{
	using namespace Corona;
	// Dismiss the picker
	[unknownPersonView dismissModalViewControllerAnimated:YES];
		
	// If the details were added to a contact or used to create a contact
	if ( person )
	{
		// We have chosen a person
		self.hasChosenPerson = true;
		
		// Dispatch data event ( if one exists )
		[self dispatchAddressBookEvent:person:"data"];
	}
}

// If allowed execute default actions such as dialing a phone number, when they select a contact property.
- (BOOL)unknownPersonViewController:(ABUnknownPersonViewController *)personViewController shouldPerformDefaultActionForPerson:(ABRecordRef)person
						   property:(ABPropertyID)property identifier:(ABMultiValueIdentifier)identifier
{
	return shouldPerformDefaultAction;
}

@end


// ----------------------------------------------------------------------------

CORONA_EXPORT
int luaopen_CoronaProvider_native_popup_addressBook( lua_State *L )
{
	return Corona::IOSAddressBookNativePopupProvider::Open( L );
}

// ----------------------------------------------------------------------------

