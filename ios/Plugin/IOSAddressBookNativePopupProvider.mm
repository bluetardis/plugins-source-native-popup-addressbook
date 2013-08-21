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

static const char kPopupName[] = "addressbook";
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
	bool result = true;
	CFErrorRef error = NULL;

	// Retrieve the pre-filled contact fields from lua (if any)
	const char *contactFirstName = luaRetrieveString( L, -1, "firstName", chosenAddressBookOption, "data", 2 );
	const char *contactMiddleName = luaRetrieveString( L, -1, "middleName", chosenAddressBookOption, "data", 2 );
	const char *contactLastName = luaRetrieveString( L, -1, "lastName", chosenAddressBookOption, "data", 2 );
	const char *contactOrganization = luaRetrieveString( L, -1, "organization", chosenAddressBookOption, "data", 2 );
	const char *contactJobTitle = luaRetrieveString( L, -1, "jobTitle", chosenAddressBookOption, "data", 2 );
	const char *contactBirthday = luaRetrieveString( L, -1, "birthday", chosenAddressBookOption, "data", 2 );
	const char *contactPhoneticFirstName = luaRetrieveString( L, -1, "phoneticFirstName", chosenAddressBookOption, "data", 2 );
	const char *contactPhoneticMiddleName = luaRetrieveString( L, -1, "phoneticMiddleName", chosenAddressBookOption, "data", 2 );
	const char *contactPhoneticLastName = luaRetrieveString( L, -1, "phoneticLastName", chosenAddressBookOption, "data", 2 );
	const char *contactPrefix = luaRetrieveString( L, -1, "prefix", chosenAddressBookOption, "data", 2 );
	const char *contactSuffix = luaRetrieveString( L, -1, "suffix", chosenAddressBookOption, "data", 2 );
	const char *contactNickname = luaRetrieveString( L, -1, "nickname", chosenAddressBookOption, "data", 2 );
	// Phone Numbers
	const char *contactPhoneIphone = luaRetrieveString( L, -1, "phoneIphone", chosenAddressBookOption, "data", 2 );
	const char *contactPhoneMobile = luaRetrieveString( L, -1, "phoneMobile", chosenAddressBookOption, "data", 2 );
	const char *contactPhoneMain = luaRetrieveString( L, -1, "phoneMain", chosenAddressBookOption, "data", 2 );
	const char *contactPhoneHome = luaRetrieveString( L, -1, "phoneHome", chosenAddressBookOption, "data", 2 );
	const char *contactPhoneWork = luaRetrieveString( L, -1, "phoneWork", chosenAddressBookOption, "data", 2 );
	// Fax Numbers
	const char *contactFaxHome = luaRetrieveString( L, -1, "faxHome", chosenAddressBookOption, "data", 2 );
	const char *contactFaxWork = luaRetrieveString( L, -1, "faxWork", chosenAddressBookOption, "data", 2 );
	const char *contactFaxOther = luaRetrieveString( L, -1, "faxOther", chosenAddressBookOption, "data", 2 );
	// Pager
	const char *contactPager = luaRetrieveString( L, -1, "pager", chosenAddressBookOption, "data", 2 );
	// Email Addresses
	const char *contactHomeEmailAddress = luaRetrieveString( L, -1, "homeEmail", chosenAddressBookOption, "data", 2 );
	const char *contactWorkEmailAddress = luaRetrieveString( L, -1, "workEmail", chosenAddressBookOption, "data", 2 );
	// Urls
	const char *contactHomePageUrl = luaRetrieveString( L, -1, "homePageUrl", chosenAddressBookOption, "data", 2 );
	const char *contactWorkUrl = luaRetrieveString( L, -1, "workUrl", chosenAddressBookOption, "data", 2 );
	const char *contactHomeUrl = luaRetrieveString( L, -1, "homeUrl", chosenAddressBookOption, "data", 2 );
	// People
	const char *contactFather = luaRetrieveString( L, -1, "father", chosenAddressBookOption, "data", 2 );
	const char *contactMother = luaRetrieveString( L, -1, "mother", chosenAddressBookOption, "data", 2 );
	const char *contactParent = luaRetrieveString( L, -1, "parent", chosenAddressBookOption, "data", 2 );
	const char *contactBrother = luaRetrieveString( L, -1, "brother", chosenAddressBookOption, "data", 2 );
	const char *contactSister = luaRetrieveString( L, -1, "sister", chosenAddressBookOption, "data", 2 );
	const char *contactChild = luaRetrieveString( L, -1, "child", chosenAddressBookOption, "data", 2 );
	const char *contactFriend = luaRetrieveString( L, -1, "friend", chosenAddressBookOption, "data", 2 );
	const char *contactSpouse = luaRetrieveString( L, -1, "spouse", chosenAddressBookOption, "data", 2 );
	const char *contactPartner = luaRetrieveString( L, -1, "partner", chosenAddressBookOption, "data", 2 );
	const char *contactAssistant = luaRetrieveString( L, -1, "assistant", chosenAddressBookOption, "data", 2 );
	const char *contactManager = luaRetrieveString( L, -1, "manager", chosenAddressBookOption, "data", 2 );
	// Addresses
	const char *contactHomeStreet = luaRetrieveString( L, -1, "homeStreet", chosenAddressBookOption, "data", 2 );
	const char *contactHomeCity = luaRetrieveString( L, -1, "homeCity", chosenAddressBookOption, "data", 2 );
	const char *contactHomeState = luaRetrieveString( L, -1, "homeState", chosenAddressBookOption, "data", 2 );
	const char *contactHomeZip = luaRetrieveString( L, -1, "homeZip", chosenAddressBookOption, "data", 2 );
	const char *contactHomeCountry = luaRetrieveString( L, -1, "homeCountry", chosenAddressBookOption, "data", 2 );
	const char *contactWorkStreet = luaRetrieveString( L, -1, "workStreet", chosenAddressBookOption, "data", 2 );
	const char *contactWorkCity = luaRetrieveString( L, -1, "workCity", chosenAddressBookOption, "data", 2 );
	const char *contactWorkState = luaRetrieveString( L, -1, "workState", chosenAddressBookOption, "data", 2 );
	const char *contactWorkZip = luaRetrieveString( L, -1, "workZip", chosenAddressBookOption, "data", 2 );
	const char *contactWorkCountry = luaRetrieveString( L, -1, "workCountry", chosenAddressBookOption, "data", 2 );
	// Social Profiles
	const char *contactSocialProfileFacebook = luaRetrieveString( L, -1, "socialFacebook", chosenAddressBookOption, "data", 2 );
	const char *contactSocialProfileTwitter = luaRetrieveString( L, -1, "socialTwitter", chosenAddressBookOption, "data", 2 );
	const char *contactSocialProfileFlickr = luaRetrieveString( L, -1, "socialFlickr", chosenAddressBookOption, "data", 2 );
	const char *contactSocialProfileLinkedIn = luaRetrieveString( L, -1, "socialLinkedIn", chosenAddressBookOption, "data", 2 );
	const char *contactSocialProfileMyspace = luaRetrieveString( L, -1, "socialMyspace", chosenAddressBookOption, "data", 2 );
	const char *contactSocialProfileSinaWeibo = luaRetrieveString( L, -1, "socialSinaWeibo", chosenAddressBookOption, "data", 2 );
	const char *contactSocialProfileGameCenter = luaRetrieveString( L, -1, "socialGameCenter", chosenAddressBookOption, "data", 2 );
	// Instant Messaging Profiles
	const char *contactInstantMessagingProfileAim = luaRetrieveString( L, -1, "instantMessagingAim", chosenAddressBookOption, "data", 2 );
	const char *contactInstantMessagingProfileFacebook = luaRetrieveString( L, -1, "instantMessagingFacebook", chosenAddressBookOption, "data", 2 );
	const char *contactInstantMessagingProfileGaduGadu = luaRetrieveString( L, -1, "instantMessagingGaduGadu", chosenAddressBookOption, "data", 2 );
	const char *contactInstantMessagingProfileGoogleTalk = luaRetrieveString( L, -1, "instantMessagingGoogleTalk", chosenAddressBookOption, "data", 2 );
	const char *contactInstantMessagingProfileICQ = luaRetrieveString( L, -1, "instantMessagingICQ", chosenAddressBookOption, "data", 2 );
	const char *contactInstantMessagingProfileJabber = luaRetrieveString( L, -1, "instantMessagingJabber", chosenAddressBookOption, "data", 2 );
	const char *contactInstantMessagingProfileMSN = luaRetrieveString( L, -1, "instantMessagingMSN", chosenAddressBookOption, "data", 2 );
	const char *contactInstantMessagingProfileQQ = luaRetrieveString( L, -1, "instantMessagingQQ", chosenAddressBookOption, "data", 2 );
	const char *contactInstantMessagingProfileSkype = luaRetrieveString( L, -1, "instantMessagingSkype", chosenAddressBookOption, "data", 2 );
	const char *contactInstantMessagingProfileYahoo = luaRetrieveString( L, -1, "instantMessagingYahoo", chosenAddressBookOption, "data", 2 );
	
	// Pop the options.data table
	lua_pop( L, 1 );
	
	// Create multi value references
	ABMutableMultiValueRef personPhoneNumbers = ABMultiValueCreateMutable(kABMultiStringPropertyType);
	ABMutableMultiValueRef personEmailAddresses = ABMultiValueCreateMutable(kABMultiStringPropertyType);
	ABMutableMultiValueRef personUrls = ABMultiValueCreateMutable(kABMultiStringPropertyType);
	ABMutableMultiValueRef personRelatedNames = ABMultiValueCreateMutable(kABMultiStringPropertyType);
	ABMutableMultiValueRef personSocialProfiles = ABMultiValueCreateMutable(kABMultiDictionaryPropertyType);
	ABMutableMultiValueRef personInstantMessagingProfiles = ABMultiValueCreateMutable(kABMultiStringPropertyType);
	ABMutableMultiValueRef personAddresses = ABMultiValueCreateMutable(kABMultiDictionaryPropertyType);
	NSMutableDictionary *personHomeAddressDictionary = [[NSMutableDictionary alloc] init];
	NSMutableDictionary *personWorkAddressDictionary = [[NSMutableDictionary alloc] init];
	
	// Names + Other \\
		
	// First Name
	if ( contactFirstName )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactFirstName];
		ABRecordSetValue(person, kABPersonFirstNameProperty, value, &error);
	}
	
	// Middle Name
	if ( contactMiddleName )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactMiddleName];
		ABRecordSetValue(person, kABPersonMiddleNameProperty, value, &error);
	}
	
	// Last Name
	if ( contactLastName )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactLastName];
		ABRecordSetValue(person, kABPersonLastNameProperty, value, &error);
	}
	
	// Organization
	if ( contactOrganization )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactOrganization];
		ABRecordSetValue(person, kABPersonOrganizationProperty, value, &error);
	}
	
	// Job Title
	if ( contactJobTitle )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactJobTitle];
		ABRecordSetValue(person, kABPersonJobTitleProperty, value, &error);
	}
	
	// Prefix
	if ( contactPrefix )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactPrefix];
		ABRecordSetValue(person, kABPersonPrefixProperty, value, &error);
	}
	
	// Suffix
	if ( contactSuffix )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactSuffix];
		ABRecordSetValue(person, kABPersonSuffixProperty, value, &error);
	}
	
	// Nickname
	if ( contactNickname )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactNickname];
		ABRecordSetValue(person, kABPersonNicknameProperty, value, &error);
	}
	
	// Phonetic First Name
	if ( contactPhoneticFirstName )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactPhoneticFirstName];
		ABRecordSetValue(person, kABPersonFirstNamePhoneticProperty, value, &error);
	}
	
	// Phonetic Middle Name
	if ( contactPhoneticMiddleName )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactPhoneticMiddleName];
		ABRecordSetValue(person, kABPersonMiddleNamePhoneticProperty, value, &error);
	}
	
	// Phonetic Last Name
	if ( contactPhoneticLastName )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactPhoneticLastName];
		ABRecordSetValue(person, kABPersonLastNamePhoneticProperty, value, &error);
	}
	
	
	//------- Related Names ---------\\
	
	// Father
	if ( contactFather )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactFather];
		ABMultiValueAddValueAndLabel(personRelatedNames, value, kABPersonFatherLabel, NULL);
	}
	
	// Mother
	if ( contactMother )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactMother];
		ABMultiValueAddValueAndLabel(personRelatedNames, value, kABPersonMotherLabel, NULL);
	}
	
	// Parent
	if ( contactParent )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactParent];
		ABMultiValueAddValueAndLabel(personRelatedNames, value, kABPersonParentLabel, NULL);
	}
	
	// Brother
	if ( contactBrother )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactBrother];
		ABMultiValueAddValueAndLabel(personRelatedNames, value, kABPersonBrotherLabel, NULL);
	}
	
	// Sister
	if ( contactSister )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactSister];
		ABMultiValueAddValueAndLabel(personRelatedNames, value, kABPersonSisterLabel, NULL);
	}
	
	// Child
	if ( contactChild )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactChild];
		ABMultiValueAddValueAndLabel(personRelatedNames, value, kABPersonChildLabel, NULL);
	}

	// Friend
	if ( contactFriend )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactFriend];
		ABMultiValueAddValueAndLabel(personRelatedNames, value, kABPersonFriendLabel, NULL);
	}

	// Spouse
	if ( contactSpouse )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactSpouse];
		ABMultiValueAddValueAndLabel(personRelatedNames, value, kABPersonSpouseLabel, NULL);
	}
	
	// Partner
	if ( contactPartner )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactPartner];
		ABMultiValueAddValueAndLabel(personRelatedNames, value, kABPersonPartnerLabel, NULL);
	}
	
	// Assistant
	if ( contactAssistant )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactAssistant];
		ABMultiValueAddValueAndLabel(personRelatedNames, value, kABPersonAssistantLabel, NULL);
	}
	
	// Manager
	if ( contactManager )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactManager];
		ABMultiValueAddValueAndLabel(personRelatedNames, value, kABPersonManagerLabel, NULL);
	}
	
	// Birthday
	if ( contactBirthday )
	{
		NSString *value = [NSString stringWithUTF8String:contactBirthday];

		NSError *dateError = nil;
		NSDate *date = nil;
		NSDataDetector *detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeDate error:&dateError];
		NSArray *matches = [detector matchesInString:value options:0 range:NSMakeRange(0, [value length])];
		
		// Get the date
		for ( NSTextCheckingResult *match in matches )
		{
			date = match.date;
			//NSLog( @"Got date: %@", match.date );
		}
		
		if ( date )
		{
			// Set the value
			ABRecordSetValue(person, kABPersonBirthdayProperty, (CFDateRef)date, &error);
		}
		else
		{
			NSLog( @"Error: %@", dateError );
		}
	}
	
	
	//------- Addresses ---------\\

	// Home Street
	if ( contactHomeStreet )
	{
		NSString *value = [NSString stringWithUTF8String:contactHomeStreet];
		[personHomeAddressDictionary setObject:value forKey:(NSString *) kABPersonAddressStreetKey];
	}
	
	// Home City
	if ( contactHomeCity )
	{
		NSString *value = [NSString stringWithUTF8String:contactHomeCity];
		[personHomeAddressDictionary setObject:value forKey:(NSString *) kABPersonAddressCityKey];
	}
	
	// Home State
	if ( contactHomeState )
	{
		NSString *value = [NSString stringWithUTF8String:contactHomeState];
		[personHomeAddressDictionary setObject:value forKey:(NSString *) kABPersonAddressStateKey];
	}
	
	// Home Zip
	if ( contactHomeZip )
	{
		NSString *value = [NSString stringWithUTF8String:contactHomeZip];
		[personHomeAddressDictionary setObject:value forKey:(NSString *) kABPersonAddressZIPKey];
	}
	
	// Home Country
	if ( contactHomeCountry )
	{
		NSString *value = [NSString stringWithUTF8String:contactHomeCountry];
		[personHomeAddressDictionary setObject:value forKey:(NSString *) kABPersonAddressCountryKey];
	}
	
	// Work Street
	if ( contactWorkStreet )
	{
		NSString *value = [NSString stringWithUTF8String:contactWorkStreet];
		[personWorkAddressDictionary setObject:value forKey:(NSString *) kABPersonAddressStreetKey];
	}
	
	// Work City
	if ( contactWorkCity )
	{
		NSString *value = [NSString stringWithUTF8String:contactWorkCity];
		[personWorkAddressDictionary setObject:value forKey:(NSString *) kABPersonAddressCityKey];
	}
	
	// Work State
	if ( contactWorkState )
	{
		NSString *value = [NSString stringWithUTF8String:contactWorkState];
		[personWorkAddressDictionary setObject:value forKey:(NSString *) kABPersonAddressStateKey];
	}
	
	// Work Zip
	if ( contactWorkZip )
	{
		NSString *value = [NSString stringWithUTF8String:contactWorkZip];
		[personWorkAddressDictionary setObject:value forKey:(NSString *) kABPersonAddressZIPKey];
	}
	
	// Work Country
	if ( contactWorkCountry )
	{
		NSString *value = [NSString stringWithUTF8String:contactWorkCountry];
		[personWorkAddressDictionary setObject:value forKey:(NSString *) kABPersonAddressCountryKey];
	}


	//------- Phone Numbers ---------\\

	
	// Phone: iPhone
	if ( contactPhoneIphone )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactPhoneIphone];
		ABMultiValueAddValueAndLabel(personPhoneNumbers, value, kABPersonPhoneIPhoneLabel, NULL);
	}
	
	// Phone: Mobile
	if ( contactPhoneMobile )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactPhoneMobile];
		ABMultiValueAddValueAndLabel(personPhoneNumbers, value, kABPersonPhoneMobileLabel, NULL);
	}
	
	// Phone: Main
	if ( contactPhoneMain )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactPhoneMain];
		ABMultiValueAddValueAndLabel(personPhoneNumbers, value, kABPersonPhoneMainLabel, NULL);
	}	
	
	// Phone: Home
	if ( contactPhoneHome )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactPhoneHome];
		ABMultiValueAddValueAndLabel(personPhoneNumbers, value, kABHomeLabel, NULL);
	}

	// Phone: Work
	if ( contactPhoneWork )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactPhoneWork];
		ABMultiValueAddValueAndLabel(personPhoneNumbers, value, kABWorkLabel, NULL);
	}

	
	//------- Fax Numbers ---------\\
	
	// Fax: Home
	if ( contactFaxHome )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactFaxHome ];
		ABMultiValueAddValueAndLabel(personPhoneNumbers, value, kABPersonPhoneHomeFAXLabel, NULL);
	}
	
	// Fax: Work
	if ( contactFaxWork )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactFaxWork ];
		ABMultiValueAddValueAndLabel(personPhoneNumbers, value, kABPersonPhoneWorkFAXLabel, NULL);
	}
	
	// Fax: Other
	if ( contactFaxOther )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactFaxOther ];
		ABMultiValueAddValueAndLabel(personPhoneNumbers, value, kABPersonPhoneOtherFAXLabel, NULL);
	}
	
	
	//------- Pager ---------\\
	
	// Pager
	if ( contactPager )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactPager ];
		ABMultiValueAddValueAndLabel(personPhoneNumbers, value, kABPersonPhonePagerLabel, NULL);
	}
	
	
	//------- Email Addresses ---------\\
	

	// Home email address
	if ( contactHomeEmailAddress )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactHomeEmailAddress];
		ABMultiValueAddValueAndLabel(personEmailAddresses, value, kABHomeLabel, NULL);
	}

	// Work email address
	if ( contactWorkEmailAddress )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactWorkEmailAddress];
		ABMultiValueAddValueAndLabel(personEmailAddresses, value, kABWorkLabel, NULL);
	}
	
	
	//------- Urls ---------\\
	
	// Home Page Url
	if ( contactHomePageUrl )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactHomePageUrl];
		ABMultiValueAddValueAndLabel(personUrls, value, kABPersonHomePageLabel, NULL);
	}
	
	// Home URL
	if ( contactHomeUrl )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactHomeUrl];
		ABMultiValueAddValueAndLabel(personUrls, value, kABHomeLabel, NULL);
	}
	
	// Work URL
	if ( contactWorkUrl )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactWorkUrl];
		ABMultiValueAddValueAndLabel(personUrls, value, kABWorkLabel, NULL);
	}
	
	//------- Instant Messaging Profiles ---------\\
	
	// Aim
	if ( contactInstantMessagingProfileAim )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactInstantMessagingProfileAim];
		ABMultiValueAddValueAndLabel(personInstantMessagingProfiles, [NSDictionary dictionaryWithObjectsAndKeys:
																	  (NSString *)kABPersonInstantMessageServiceAIM, kABPersonInstantMessageServiceKey,
																	  value, kABPersonInstantMessageUsernameKey,
																	  nil], kABPersonInstantMessageServiceAIM, NULL);
	}
	
	// Facebook
	if ( contactInstantMessagingProfileFacebook )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactInstantMessagingProfileFacebook];
		ABMultiValueAddValueAndLabel(personInstantMessagingProfiles, [NSDictionary dictionaryWithObjectsAndKeys:
																	  (NSString *)kABPersonInstantMessageServiceFacebook, kABPersonInstantMessageServiceKey,
																	  value, kABPersonInstantMessageUsernameKey,
																	  nil], kABPersonInstantMessageServiceFacebook, NULL);
	}
	
	// Gadu Gadu
	if ( contactInstantMessagingProfileGaduGadu )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactInstantMessagingProfileGaduGadu];
		ABMultiValueAddValueAndLabel(personInstantMessagingProfiles, [NSDictionary dictionaryWithObjectsAndKeys:
																	  (NSString *)kABPersonInstantMessageServiceGaduGadu, kABPersonInstantMessageServiceKey,
																	  value, kABPersonInstantMessageUsernameKey,
																	  nil], kABPersonInstantMessageServiceGaduGadu, NULL);
	}
	
	// Google Talk
	if ( contactInstantMessagingProfileGoogleTalk )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactInstantMessagingProfileGoogleTalk];
		ABMultiValueAddValueAndLabel(personInstantMessagingProfiles, [NSDictionary dictionaryWithObjectsAndKeys:
																	  (NSString *)kABPersonInstantMessageServiceGoogleTalk, kABPersonInstantMessageServiceKey,
																	  value, kABPersonInstantMessageUsernameKey,
																	  nil], kABPersonInstantMessageServiceGoogleTalk, NULL);
	}
	
	// ICQ
	if ( contactInstantMessagingProfileICQ )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactInstantMessagingProfileICQ];
		ABMultiValueAddValueAndLabel(personInstantMessagingProfiles, [NSDictionary dictionaryWithObjectsAndKeys:
																	  (NSString *)kABPersonInstantMessageServiceICQ, kABPersonInstantMessageServiceKey,
																	  value, kABPersonInstantMessageUsernameKey,
																	  nil], kABPersonInstantMessageServiceICQ, NULL);
	}
	
	// Jabber
	if ( contactInstantMessagingProfileJabber )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactInstantMessagingProfileJabber];
		ABMultiValueAddValueAndLabel(personInstantMessagingProfiles, [NSDictionary dictionaryWithObjectsAndKeys:
																	  (NSString *)kABPersonInstantMessageServiceJabber, kABPersonInstantMessageServiceKey,
																	  value, kABPersonInstantMessageUsernameKey,
																	  nil], kABPersonInstantMessageServiceJabber, NULL);
	}
	
	// MSN
	if ( contactInstantMessagingProfileMSN )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactInstantMessagingProfileMSN];
		ABMultiValueAddValueAndLabel(personInstantMessagingProfiles, [NSDictionary dictionaryWithObjectsAndKeys:
																	  (NSString *)kABPersonInstantMessageServiceMSN, kABPersonInstantMessageServiceKey,
																	  value, kABPersonInstantMessageUsernameKey,
																	  nil], kABPersonInstantMessageServiceMSN, NULL);
	}
	
	// QQ
	if ( contactInstantMessagingProfileQQ )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactInstantMessagingProfileQQ];
		ABMultiValueAddValueAndLabel(personInstantMessagingProfiles, [NSDictionary dictionaryWithObjectsAndKeys:
																	  (NSString *)kABPersonInstantMessageServiceQQ, kABPersonInstantMessageServiceKey,
																	  value, kABPersonInstantMessageUsernameKey,
																	  nil], kABPersonInstantMessageServiceQQ, NULL);
	}
	
	// Skype
	if ( contactInstantMessagingProfileSkype )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactInstantMessagingProfileSkype];
		ABMultiValueAddValueAndLabel(personInstantMessagingProfiles, [NSDictionary dictionaryWithObjectsAndKeys:
																	  (NSString *)kABPersonInstantMessageServiceSkype, kABPersonInstantMessageServiceKey,
																	  value, kABPersonInstantMessageUsernameKey,
																	  nil], kABPersonInstantMessageServiceSkype, NULL);
	}
	
	// Yahoo
	if ( contactInstantMessagingProfileYahoo )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactInstantMessagingProfileYahoo];
		ABMultiValueAddValueAndLabel(personInstantMessagingProfiles, [NSDictionary dictionaryWithObjectsAndKeys:
																	  (NSString *)kABPersonInstantMessageServiceYahoo, kABPersonInstantMessageServiceKey,
																	  value, kABPersonInstantMessageUsernameKey,
																	  nil], kABPersonInstantMessageServiceYahoo, NULL);
	}
	
	
	//------- Social Profiles ---------\\
	
	// Facebook
	if ( contactSocialProfileFacebook )
	{
		NSString *value = [NSString stringWithUTF8String:contactSocialProfileFacebook];
		ABMultiValueAddValueAndLabel(personSocialProfiles, [NSDictionary dictionaryWithObjectsAndKeys:
															(NSString *)kABPersonSocialProfileServiceFacebook, kABPersonSocialProfileServiceKey,
															value, kABPersonSocialProfileUsernameKey,
															nil], kABPersonSocialProfileServiceFacebook, NULL);
	}
	
	// Twitter
	if ( contactSocialProfileTwitter )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactSocialProfileTwitter];
		ABMultiValueAddValueAndLabel(personSocialProfiles, [NSDictionary dictionaryWithObjectsAndKeys:
															(NSString *)kABPersonSocialProfileServiceTwitter, kABPersonSocialProfileServiceKey,
															value, kABPersonSocialProfileUsernameKey,
															nil], kABPersonSocialProfileServiceTwitter, NULL);
	}
	
	// Flickr
	if ( contactSocialProfileFlickr )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactSocialProfileFlickr];
		ABMultiValueAddValueAndLabel(personSocialProfiles, [NSDictionary dictionaryWithObjectsAndKeys:
															(NSString *)kABPersonSocialProfileServiceFlickr, kABPersonSocialProfileServiceKey,
															value, kABPersonSocialProfileUsernameKey,
															nil], kABPersonSocialProfileServiceFlickr, NULL);
	}
	
	// LinkedIn
	if ( contactSocialProfileLinkedIn )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactSocialProfileLinkedIn];
		ABMultiValueAddValueAndLabel(personSocialProfiles, [NSDictionary dictionaryWithObjectsAndKeys:
															(NSString *)kABPersonSocialProfileServiceLinkedIn, kABPersonSocialProfileServiceKey,
															value, kABPersonSocialProfileUsernameKey,
															nil], kABPersonSocialProfileServiceLinkedIn, NULL);
	}
	
	// Myspace
	if ( contactSocialProfileMyspace )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactSocialProfileMyspace];
		ABMultiValueAddValueAndLabel(personSocialProfiles, [NSDictionary dictionaryWithObjectsAndKeys:
															(NSString *)kABPersonSocialProfileServiceMyspace, kABPersonSocialProfileServiceKey,
															value, kABPersonSocialProfileUsernameKey,
															nil], kABPersonSocialProfileServiceMyspace, NULL);
	}
	
	// Sina Weibo
	if ( contactSocialProfileSinaWeibo )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactSocialProfileSinaWeibo];
		ABMultiValueAddValueAndLabel(personSocialProfiles, [NSDictionary dictionaryWithObjectsAndKeys:
															(NSString *)kABPersonSocialProfileServiceSinaWeibo, kABPersonSocialProfileServiceKey,
															value, kABPersonSocialProfileUsernameKey,
															nil], kABPersonSocialProfileServiceSinaWeibo, NULL);
	}
	
	// Game Center
	if ( contactSocialProfileGameCenter )
	{
		CFStringRef value = (CFStringRef)[NSString stringWithUTF8String:contactSocialProfileGameCenter];
		ABMultiValueAddValueAndLabel(personSocialProfiles, [NSDictionary dictionaryWithObjectsAndKeys:
															(NSString *)kABPersonSocialProfileServiceGameCenter, kABPersonSocialProfileServiceKey,
															value, kABPersonSocialProfileUsernameKey,
															nil], kABPersonSocialProfileServiceGameCenter, NULL);
	}
	

	//------- ! Set Values to New Contact Form ! ---------\\
	
	
	// Set Person Phone Numbers
	if ( ABMultiValueGetCount(personPhoneNumbers) >= 1 )
	{
		ABRecordSetValue(person, kABPersonPhoneProperty, personPhoneNumbers, &error);
	}
	// Set Person Email Addresses
	if ( ABMultiValueGetCount(personEmailAddresses) >= 1 )
	{
		ABRecordSetValue(person, kABPersonEmailProperty, personEmailAddresses, &error);
	}
	// Set Person Url's
	if ( ABMultiValueGetCount(personUrls) >= 1 )
	{
		ABRecordSetValue(person, kABPersonURLProperty, personUrls, &error);
	}
	// Set Person Addresses
	if ( [personHomeAddressDictionary count] >= 1 || [personWorkAddressDictionary count] >= 1 )
	{
		if ( [personHomeAddressDictionary count] >= 1 )
		{
			ABMultiValueAddValueAndLabel(personAddresses, personHomeAddressDictionary, kABHomeLabel, NULL);
		}
		if ( [personWorkAddressDictionary count] >= 1 )
		{
			ABMultiValueAddValueAndLabel(personAddresses, personWorkAddressDictionary, kABWorkLabel, NULL);
		}
		ABRecordSetValue(person, kABPersonAddressProperty, personAddresses, &error);
	}
	// Set Person Releated People
	if ( ABMultiValueGetCount(personRelatedNames) >= 1 )
	{
		ABRecordSetValue(person, kABPersonRelatedNamesProperty, personRelatedNames, &error);
	}
	// Set Person Phone Social Profiles
	if ( ABMultiValueGetCount(personSocialProfiles) >= 1 )
	{
		ABRecordSetValue(person, kABPersonSocialProfileProperty, personSocialProfiles, &error);
	}
	// Set Person Instant Messaging Profiles
	if ( ABMultiValueGetCount(personInstantMessagingProfiles) >= 1 )
	{
		ABRecordSetValue(person, kABPersonInstantMessageProperty, personInstantMessagingProfiles, &error);
	}
	
	
	// Error
	if ( error )
	{
		NSLog( @"Address Book: Adding details failed %@", error );
		result = false;
	}

	// Cleanup
	CFRelease( personPhoneNumbers );
	CFRelease( personEmailAddresses );
	CFRelease( personUrls );
	CFRelease( personAddresses );
	CFRelease( personRelatedNames );
	CFRelease( personSocialProfiles );
	CFRelease( personInstantMessagingProfiles );
	[personHomeAddressDictionary release];
	personHomeAddressDictionary = nil;
	[personWorkAddressDictionary release];
	personWorkAddressDictionary = nil;

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
		if ( message )
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

	if ( context && 0 == strcmp( "addressbook", popUpName ) )
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


#include <string>
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
			// event.data table
			lua_newtable( self.luaState );

			// Create multi value references
			CFArrayRef linkedContacts = ABPersonCopyArrayOfAllLinkedPeople(person);
			
			// Retrieve information from linked contacts
			for ( CFIndex i = 0; i < CFArrayGetCount(linkedContacts); i ++ )
			{
				// The linked contact
				ABRecordRef linkedContact = CFArrayGetValueAtIndex(linkedContacts, i);
				
				// Retrieve contact details
				NSString *contactFirstName = (NSString *)ABRecordCopyValue(linkedContact, kABPersonFirstNameProperty);
				NSString *contactMiddleName = (NSString *)ABRecordCopyValue(linkedContact, kABPersonMiddleNameProperty);
				NSString *contactLastName = (NSString *)ABRecordCopyValue(linkedContact, kABPersonLastNameProperty);
				NSString *contactSuffix = (NSString *)ABRecordCopyValue(linkedContact, kABPersonSuffixProperty);
				NSString *contactPrefix = (NSString *)ABRecordCopyValue(linkedContact, kABPersonSuffixProperty);
				NSString *contactPhoneticFirstName = (NSString *)ABRecordCopyValue(linkedContact, kABPersonFirstNamePhoneticProperty);
				NSString *contactPhoneticMiddleName = (NSString *)ABRecordCopyValue(linkedContact, kABPersonMiddleNamePhoneticProperty);
				NSString *contactPhoneticLastName = (NSString *)ABRecordCopyValue(linkedContact, kABPersonLastNamePhoneticProperty);			
				NSString *contactJobTitle = (NSString *)ABRecordCopyValue(linkedContact, kABPersonJobTitleProperty);
				NSString *contactOrganization = (NSString *)ABRecordCopyValue(linkedContact, kABPersonOrganizationProperty);
				NSString *contactDepartment = (NSString *)ABRecordCopyValue(linkedContact, kABPersonDepartmentProperty);
				NSString *contactNickName = (NSString *)ABRecordCopyValue(linkedContact, kABPersonNicknameProperty);
				NSDate *contactBirthday = (NSDate *)(ABRecordCopyValue(linkedContact, kABPersonBirthdayProperty));
				
			
				// Add key/value pairs to the event.data table
				if ( contactFirstName )
				{
					lua_pushstring( self.luaState, [contactFirstName UTF8String] ); // Value
					lua_setfield( self.luaState, -2, "firstName" ); // Key
				}
				
				if ( contactMiddleName )
				{
					lua_pushstring( self.luaState, [contactMiddleName UTF8String] ); // Value
					lua_setfield( self.luaState, -2, "middleName" ); // Key
				}

				if ( contactLastName )
				{
					lua_pushstring( self.luaState,  [contactLastName UTF8String] ); // Value
					lua_setfield( self.luaState, -2, "lastName" ); // Key
				}
				
				if ( contactSuffix )
				{
					lua_pushstring( self.luaState, [contactSuffix UTF8String] ); // Value
					lua_setfield( self.luaState, -2, "suffix" ); // Key
				}
				
				if ( contactPrefix )
				{
					lua_pushstring( self.luaState, [contactPrefix UTF8String] ); // Value
					lua_setfield( self.luaState, -2, "prefix" ); // Key
				}
				
				if ( contactPhoneticFirstName )
				{
					lua_pushstring( self.luaState, [contactPhoneticFirstName UTF8String] ); // Value
					lua_setfield( self.luaState, -2, "phoneticFirstName" ); // Key
				}
				
				if ( contactPhoneticMiddleName )
				{
					lua_pushstring( self.luaState, [contactPhoneticMiddleName UTF8String] ); // Value
					lua_setfield( self.luaState, -2, "phoneticMiddleName" ); // Key
				}
				
				if ( contactPhoneticLastName )
				{
					lua_pushstring( self.luaState, [contactPhoneticLastName UTF8String] ); // Value
					lua_setfield( self.luaState, -2, "phoneticLastName" ); // Key
				}
				
				if ( contactJobTitle )
				{
					lua_pushstring( self.luaState, [contactJobTitle UTF8String] ); // Value
					lua_setfield( self.luaState, -2, "jobTitle" ); // Key
				}
				
				if ( contactOrganization )
				{
					lua_pushstring( self.luaState, [contactOrganization UTF8String] ); // Value
					lua_setfield( self.luaState, -2, "organization" ); // Key
				}
				
				if ( contactDepartment )
				{
					lua_pushstring( self.luaState, [contactDepartment UTF8String] ); // Value
					lua_setfield( self.luaState, -2, "department" ); // Key
				}

				if ( contactBirthday )
				{
					NSString *dateValue = [NSDateFormatter localizedStringFromDate:contactBirthday dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterNoStyle];
					lua_pushstring( self.luaState, [dateValue UTF8String] ); // Value
					lua_setfield( self.luaState, -2, "birthday" ); // Key
				}
				
				if ( contactNickName )
				{
					lua_pushstring( self.luaState, [contactNickName UTF8String] ); // Value
					lua_setfield( self.luaState, -2, "nickName" ); // Key
				}
				
				//----------- MULTIVALUE REFS-----------//
				
				// Retrieve and push url's
				ABMultiValueRef allUrls = ABRecordCopyValue(linkedContact, kABPersonURLProperty);
				
				// Loop through the urls
				for ( int j = 0; j < ABMultiValueGetCount( allUrls ); j ++ )
				{
					NSString *url = (NSString *)ABMultiValueCopyValueAtIndex(allUrls, j);
					NSString *key = [NSString stringWithFormat:@"%s%d", "otherUrl", ( -2 ) + j];
					
					switch( j )
					{
						case 0:
							key = @"homePageUrl";
							break;
							
						case 1:
							key = @"homeUrl";
							break;
							
						case 2:
							key = @"workUrl";
							break;
					}
					
					lua_pushstring( self.luaState, [url UTF8String] ); // Value
					lua_setfield( self.luaState, -2, [key UTF8String] ); // Key
				}
				
				
				// Retrieve and push instant messaging profiles
				ABMultiValueRef instantMessageProfiles = ABRecordCopyValue(linkedContact, kABPersonInstantMessageProperty);
				
				// Loop through the instant message profiles
				for ( int j = 0; j < ABMultiValueGetCount( instantMessageProfiles ); j ++ )
				{
					NSDictionary *socialDictionary = [(NSDictionary*)ABMultiValueCopyValueAtIndex(instantMessageProfiles, j) autorelease];
					NSString *dictionaryService = [socialDictionary objectForKey:@"service"];
					NSString *dictionaryUserName = [socialDictionary objectForKey:@"username"];
					
					// Create provider table
					lua_newtable( self.luaState );
					// Create inner table
					lua_newtable( self.luaState );
					
					lua_pushstring( self.luaState, [dictionaryUserName UTF8String] ); // Value
					lua_setfield( self.luaState, -2, "username" ); // Key
					
					// Set inner table
					lua_rawseti( self.luaState, -2, 1 );
					
					// Set outer table
					lua_setfield( self.luaState, -2, [dictionaryService UTF8String] );
				}
			
			
				// Retrieve and push social profiles
				ABMultiValueRef socialProfiles = ABRecordCopyValue(linkedContact, kABPersonSocialProfileProperty);

				// Loop through the social profiles
				for ( int j = 0; j < ABMultiValueGetCount( socialProfiles ); j ++ )
				{
					NSDictionary *socialDictionary = [(NSDictionary*)ABMultiValueCopyValueAtIndex(socialProfiles, j) autorelease];
					NSString *dictionaryService = [socialDictionary objectForKey:@"service"];
					NSString *dictionaryUserName = [socialDictionary objectForKey:@"username"];
					NSString *dictionaryUrl = [socialDictionary objectForKey:@"url"];
					
					// Create provider table
					lua_newtable( self.luaState );
					// Create inner table
					lua_newtable( self.luaState );
					
					lua_pushstring( self.luaState, [dictionaryUrl UTF8String] ); // Value
					lua_setfield( self.luaState, -2, "url" ); // Key
					
					lua_pushstring( self.luaState, [dictionaryUserName UTF8String] ); // Value
					lua_setfield( self.luaState, -2, "username" ); // Key
					
					// Set inner table
					lua_rawseti( self.luaState, -2, 1 );
					
					// Set outer table
					lua_setfield( self.luaState, -2, [dictionaryService UTF8String] );
				}
			
			
				// Retrieve and push related names
				ABMultiValueRef relatedNames = ABRecordCopyValue(linkedContact, kABPersonRelatedNamesProperty);
			
				// Loop through the related names
				for ( int j = 0; j < ABMultiValueGetCount( relatedNames ); j ++ )
				{
					NSString *relatedNameLabel = [(NSString*)ABMultiValueCopyLabelAtIndex(relatedNames, j) autorelease];
					NSString *relatedNameString = [(NSString*)ABMultiValueCopyValueAtIndex(relatedNames, j) autorelease];
	 
					if ( [relatedNameLabel isEqualToString:(NSString *)kABPersonParentLabel] )
					{
						lua_pushstring( self.luaState, [relatedNameString UTF8String] ); // Value
						lua_setfield( self.luaState, -2, "parent" ); // Key
					}
					else if ( [relatedNameLabel isEqualToString:(NSString *)kABPersonFatherLabel] )
					{
						lua_pushstring( self.luaState, [relatedNameString UTF8String] ); // Value
						lua_setfield( self.luaState, -2, "father" ); // Key
					}
					else if ( [relatedNameLabel isEqualToString:(NSString *)kABPersonMotherLabel] )
					{
						lua_pushstring( self.luaState, [relatedNameString UTF8String] ); // Value
						lua_setfield( self.luaState, -2, "mother" ); // Key
					}
					else if ( [relatedNameLabel isEqualToString:(NSString *)kABPersonSisterLabel] )
					{
						lua_pushstring( self.luaState, [relatedNameString UTF8String] ); // Value
						lua_setfield( self.luaState, -2, "sister" ); // Key
					}
					else if ( [relatedNameLabel isEqualToString:(NSString *)kABPersonBrotherLabel] )
					{
						lua_pushstring( self.luaState, [relatedNameString UTF8String] ); // Value
						lua_setfield( self.luaState, -2, "brother" ); // Key
					}
					else if ( [relatedNameLabel isEqualToString:(NSString *)kABPersonChildLabel] )
					{
						lua_pushstring( self.luaState, [relatedNameString UTF8String] ); // Value
						lua_setfield( self.luaState, -2, "child" ); // Key
					}
					else if ( [relatedNameLabel isEqualToString:(NSString *)kABPersonFriendLabel] )
					{
						lua_pushstring( self.luaState, [relatedNameString UTF8String] ); // Value
						lua_setfield( self.luaState, -2, "friend" ); // Key
					}
					else if ( [relatedNameLabel isEqualToString:(NSString *)kABPersonSpouseLabel] )
					{
						lua_pushstring( self.luaState, [relatedNameString UTF8String] ); // Value
						lua_setfield( self.luaState, -2, "spouse" ); // Key
					}
					else if ( [relatedNameLabel isEqualToString:(NSString *)kABPersonPartnerLabel] )
					{
						lua_pushstring( self.luaState, [relatedNameString UTF8String] ); // Value
						lua_setfield( self.luaState, -2, "partner" ); // Key
					}
					else if ( [relatedNameLabel isEqualToString:(NSString *)kABPersonAssistantLabel] )
					{
						lua_pushstring( self.luaState, [relatedNameString UTF8String] ); // Value
						lua_setfield( self.luaState, -2, "assistant" ); // Key
					}
					else if ( [relatedNameLabel isEqualToString:(NSString *)kABPersonManagerLabel] )
					{
						lua_pushstring( self.luaState, [relatedNameString UTF8String] ); // Value
						lua_setfield( self.luaState, -2, "manager" ); // Key
					}
				}
				

				// Retrieve and push addresses
				ABMultiValueRef addresses = ABRecordCopyValue(linkedContact, kABPersonAddressProperty);
				
				// Loop through the addresses
				for ( int j = 0; j < ABMultiValueGetCount( addresses ); j ++ )		
				{
					CFDictionaryRef dict = (CFDictionaryRef)ABMultiValueCopyValueAtIndex(addresses, j);
					
					NSString *street = [(NSString *)CFDictionaryGetValue(dict, kABPersonAddressStreetKey) copy];
					NSString *city = [(NSString *)CFDictionaryGetValue(dict, kABPersonAddressCityKey) copy];
					NSString *state = [(NSString *)CFDictionaryGetValue(dict, kABPersonAddressStateKey) copy];
					NSString *zipCode = [(NSString *)CFDictionaryGetValue(dict, kABPersonAddressZIPKey) copy];
					NSString *country = [(NSString *)CFDictionaryGetValue(dict, kABPersonAddressCountryKey) copy];

					NSString *streetKey = [NSString stringWithFormat:@"%s%d", "otherStreet", ( -1 ) + j];
					NSString *cityKey = [NSString stringWithFormat:@"%s%d", "otherCity", ( -1 ) + j];
					NSString *stateKey = [NSString stringWithFormat:@"%s%d", "otherState", ( -1 ) + j];
					NSString *zipKey = [NSString stringWithFormat:@"%s%d", "otherZip", ( -1 ) + j];
					NSString *countryKey = [NSString stringWithFormat:@"%s%d", "otherCountry", ( -1 ) + j];
					
					switch( j )
					{
						case 0:
							streetKey = @"homeStreet";
							cityKey = @"homeCity";
							stateKey = @"homeState";
							zipKey = @"homeZip";
							countryKey = @"homeCountry";
							break;
							
						case 1:
							streetKey = @"workStreet";
							cityKey = @"workCity";
							stateKey = @"workState";
							zipKey = @"workZip";
							countryKey = @"workCountry";
							break;
					}
					
					// Street
					lua_pushstring( self.luaState, [street UTF8String] ); // Value
					lua_setfield( self.luaState, -2, [streetKey UTF8String] ); // Key
					
					// City
					lua_pushstring( self.luaState, [city UTF8String] ); // Value
					lua_setfield( self.luaState, -2, [cityKey UTF8String] ); // Key
					
					// State
					lua_pushstring( self.luaState, [state UTF8String] ); // Value
					lua_setfield( self.luaState, -2, [stateKey UTF8String] ); // Key
					
					// Zip
					lua_pushstring( self.luaState, [zipCode UTF8String] ); // Value
					lua_setfield( self.luaState, -2, [zipKey UTF8String] ); // Key
					
					// Country
					lua_pushstring( self.luaState, [country UTF8String] ); // Value
					lua_setfield( self.luaState, -2, [countryKey UTF8String] ); // Key
				}
				
			
				// Retrieve and push email addresses
				ABMultiValueRef emailAddresses = ABRecordCopyValue(linkedContact, kABPersonEmailProperty);
				
				// Loop through the emails
				for ( int j = 0; j < ABMultiValueGetCount( emailAddresses ); j ++ )
				{
					NSString *email = (NSString *)ABMultiValueCopyValueAtIndex(emailAddresses, j);
					NSString *key = [NSString stringWithFormat:@"%s%d", "otherEmail", ( -1 ) + j];
					
					if ( j == 0 ) key = @"homeEmail";
					else if ( j == 1 ) key = @"workEmail";
					
					lua_pushstring( self.luaState, [email UTF8String] ); // Value
					lua_setfield( self.luaState, -2, [key UTF8String] ); // Key
				}
				

				// Retrieve and push phone numbers
				ABMultiValueRef phoneNumbers = ABRecordCopyValue(linkedContact, kABPersonPhoneProperty);
				
				// Loop through the phone numbers
				for ( int j = 0; j < ABMultiValueGetCount( phoneNumbers ); j ++ )
				{
					NSString *phone = (NSString *)ABMultiValueCopyValueAtIndex(phoneNumbers, j);
					NSString *key = [NSString stringWithFormat:@"%s%d", "otherPhone", ( -8 ) + j];
					
					switch( j )
					{
						case 0:
							key = @"phoneMobile";
							break;
						
						case 1:
							key = @"phoneIphone";
							break;
						
						case 2:
							key = @"phoneHome";
							break;
							
						case 3:
							key = @"phoneWork";
							break;
							
						case 4:
							key = @"phoneMain";
							break;
							
						case 5:
							key = @"faxHome";
							break;
							
						case 6:
							key = @"faxWork";
							break;
						 
						case 7:
							key = @"faxOther";
							break;
							
						case 8:
							key = @"pager";
							break;
					}
									
					lua_pushstring( self.luaState, [phone UTF8String] ); // Value
					lua_setfield( self.luaState, -2, [key UTF8String] ); // Key
				}
				
			
				// Retrieve and push dates
				ABMultiValueRef dates = ABRecordCopyValue(linkedContact, kABPersonDateProperty);
				
				// Loop through the dates
				for ( int j = 0; j < ABMultiValueGetCount( dates ); j ++ )
				{
					ABMultiValueRef anniversaries = ABRecordCopyValue(person, kABPersonDateProperty);
					
					for (CFIndex i = 0; i < ABMultiValueGetCount(anniversaries); j ++ )
					{
						NSDate *anniversaryDate = (NSDate *)ABMultiValueCopyValueAtIndex(anniversaries, j);
						NSString *dateValue = [NSDateFormatter localizedStringFromDate:anniversaryDate dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterNoStyle];
						NSString *dateKey = [NSString stringWithFormat:@"%s%d", "otherDate", j];

						if ( j == 0 ) dateKey = @"anniversary";
								
						lua_pushstring( self.luaState, [dateValue UTF8String] ); // Value
						lua_setfield( self.luaState, -2, [dateKey UTF8String] ); // Key
					}
				}
			}

			// Set event.data
			lua_setfield( self.luaState, -2, "data" );
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
int luaopen_CoronaProvider_native_popup_addressbook( lua_State *L )
{
	return Corona::IOSAddressBookNativePopupProvider::Open( L );
}

// ----------------------------------------------------------------------------

