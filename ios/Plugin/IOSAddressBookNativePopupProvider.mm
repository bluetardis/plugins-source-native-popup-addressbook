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
@property (nonatomic) Corona::Lua::Ref listenerRef; // Reference to store our onComplete function

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

// Get a lua string
static const char *
luaGetString( lua_State *L, int index )
{
	const char *result = lua_tostring( L, index );
	return result;
}


// Get a lua bool
static bool
luaGetBool( lua_State *L, int index )
{
	bool result = lua_toboolean( L, index );
	return result;
}


// Get a lua string from a field
static const char *
luaGetStringFromField( lua_State *L, int index, const char *field )
{
	const char *result = NULL;
	
	// Get the field
	lua_getfield( L, index, field );
	if ( lua_isstring( L, -1 ) )
	{
		result = luaGetString( L, -1 );
	}
	else
	{
		if ( ! lua_isnoneornil( L, -1 ) )
		{
			luaL_error( L, "'%s' must be a string value", field );
		}
	}
	
	// Pop the field
	lua_pop( L, 1 );
	
	return result;
}

	
// Get a lua bool from a field
static bool
luaGetBoolFromField( lua_State *L, int index, const char *field )
{
	bool result = false;
	
	// Get the field
	lua_getfield( L, index, field );
	if ( lua_isboolean( L, -1 ) )
	{
		result = luaGetBool( L, -1 );
	}
	else
	{
		if ( ! lua_isnoneornil( L, -1 ) )
		{
			luaL_error( L, "'%s' must be a boolean value", field );
		}
	}
	
	// Pop the field
	lua_pop( L, 1 );

	return result;
}


// Get options table passed from lua
static int
getContactOptions( lua_State *L, CoronaAddressBookDelegate *delegate, const char *viewType, const char *chosenAddressBookOption )
{
	// Only get the boolean values that we will be using for the chosen contact view
	if ( lua_istable( L, 2 ) )
	{
		// Pick contact
		if ( 0 == strcmp( kOptionPickContact, viewType ) )
		{
			// Get hideDetails bool from lua, then set it
			delegate.shouldHideDetails = luaGetBoolFromField( L, 2, "hideDetails" );
			// Get performDefaultAction bool from lua, then set it
			delegate.shouldPerformDefaultAction = luaGetBoolFromField( L, 2, "performDefaultAction" );
		}
		// View contact
		else if ( 0 == strcmp( kOptionViewContact, viewType ) )
		{
			// Get performDefaultAction bool from lua, then set it
			delegate.shouldPerformDefaultAction = luaGetBoolFromField( L, 2, "performDefaultAction" );
			// Get isEditable bool from lua, then set it
			delegate.shouldAllowContactEditing = luaGetBoolFromField( L, 2, "isEditable" );
		}
		// Unknown contact
		else if ( 0 == strcmp( kOptionUnknownContact, viewType ) )
		{
			// Get performDefaultAction bool from lua, then set it
			delegate.shouldPerformDefaultAction = luaGetBoolFromField( L, 2, "performDefaultAction" );
			// Get shouldAllowActions bool from lua, then set it
			delegate.shouldAllowActions = luaGetBoolFromField( L, 2, "allowsActions" );
			// Get shouldAllowAdding bool from lua, then set it
			delegate.shouldAllowAdding = luaGetBoolFromField( L, 2, "allowsAdding" );
		}
	}
    
	return 0;
}


// Get "filter" table passed from lua
static int
getContactFilters( lua_State *L, CoronaAddressBookDelegate *delegate, const char *chosenAddressBookOption )
{
	// Get filter array (if it is a table)
	if ( lua_istable( L, 2 ) )
	{
		// Options table exists, retrieve name key
		lua_getfield( L, 2, "filter" );

		// If the filter table exists
		if ( lua_istable( L, -1 ) )
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
			
			// Pop the options.filter table
			lua_pop( L, 1 );
		}

		// If there is an options table & there is filter passed and the filter defined isn't a table
		if ( lua_istable( L, 2 ) && ! lua_istable( L, -1 ) && ! lua_isnoneornil( L, -1 ) )
		{
			luaL_error( L, "'Filter' passed to %s options must be a table, and must contain strings identifiying which properties you wish to display", chosenAddressBookOption );
		}
	}

	return 0;
}
	

// Helper function for setting contact details. Used in newContact and unknownContact
static int
setContactDetails( lua_State *L, ABRecordRef person, const char *chosenAddressBookOption )
{
	bool result = true;
	CFErrorRef error = NULL;
	
	// Retrieve the pre-filled contact fields from lua (if any)
	if ( lua_istable( L, 2 ) )
	{
		// Get the "data" table
		lua_getfield( L, 2, "data" );
		
		if ( lua_istable( L, -1 ) )
		{
			// Retrieve the pre-filled contact fields from lua (if any)
			const char *contactFirstName = luaGetStringFromField( L, -1, "firstName" );
			const char *contactMiddleName = luaGetStringFromField( L, -1, "middleName" );
			const char *contactLastName = luaGetStringFromField( L, -1, "lastName" );
			const char *contactOrganization = luaGetStringFromField( L, -1, "organization" );
			const char *contactJobTitle = luaGetStringFromField( L, -1, "jobTitle" );
			const char *contactBirthday = luaGetStringFromField( L, -1, "birthday" );
			const char *contactPhoneticFirstName = luaGetStringFromField( L, -1, "phoneticFirstName" );
			const char *contactPhoneticMiddleName = luaGetStringFromField( L, -1, "phoneticMiddleName" );
			const char *contactPhoneticLastName = luaGetStringFromField( L, -1, "phoneticLastName" );
			const char *contactPrefix = luaGetStringFromField( L, -1, "prefix" );
			const char *contactSuffix = luaGetStringFromField( L, -1, "suffix" );
			const char *contactNickname = luaGetStringFromField( L, -1, "nickname" );
			// Phone Numbers
			const char *contactPhoneIphone = luaGetStringFromField( L, -1, "phoneIphone" );
			const char *contactPhoneMobile = luaGetStringFromField( L, -1, "phoneMobile" );
			const char *contactPhoneMain = luaGetStringFromField( L, -1, "phoneMain" );
			const char *contactPhoneHome = luaGetStringFromField( L, -1, "phoneHome" );
			const char *contactPhoneWork = luaGetStringFromField( L, -1, "phoneWork" );
			// Fax Numbers
			const char *contactFaxHome = luaGetStringFromField( L, -1, "faxHome" );
			const char *contactFaxWork = luaGetStringFromField( L, -1, "faxWork" );
			const char *contactFaxOther = luaGetStringFromField( L, -1, "faxOther" );
			// Pager
			const char *contactPager = luaGetStringFromField( L, -1, "pager" );
			// Email Addresses
			const char *contactHomeEmailAddress = luaGetStringFromField( L, -1, "homeEmail" );
			const char *contactWorkEmailAddress = luaGetStringFromField( L, -1, "workEmail" );
			// Urls
			const char *contactHomePageUrl = luaGetStringFromField( L, -1, "homePageUrl" );
			const char *contactWorkUrl = luaGetStringFromField( L, -1, "workUrl" );
			const char *contactHomeUrl = luaGetStringFromField( L, -1, "homeUrl" );
			// People
			const char *contactFather = luaGetStringFromField( L, -1, "father" );
			const char *contactMother = luaGetStringFromField( L, -1, "mother" );
			const char *contactParent = luaGetStringFromField( L, -1, "parent" );
			const char *contactBrother = luaGetStringFromField( L, -1, "brother" );
			const char *contactSister = luaGetStringFromField( L, -1, "sister" );
			const char *contactChild = luaGetStringFromField( L, -1, "child" );
			const char *contactFriend = luaGetStringFromField( L, -1, "friend" );
			const char *contactSpouse = luaGetStringFromField( L, -1, "spouse" );
			const char *contactPartner = luaGetStringFromField( L, -1, "partner" );
			const char *contactAssistant = luaGetStringFromField( L, -1, "assistant" );
			const char *contactManager = luaGetStringFromField( L, -1, "manager" );
			// Addresses
			const char *contactHomeStreet = luaGetStringFromField( L, -1, "homeStreet" );
			const char *contactHomeCity = luaGetStringFromField( L, -1, "homeCity" );
			const char *contactHomeState = luaGetStringFromField( L, -1, "homeState" );
			const char *contactHomeZip = luaGetStringFromField( L, -1, "homeZip" );
			const char *contactHomeCountry = luaGetStringFromField( L, -1, "homeCountry" );
			const char *contactWorkStreet = luaGetStringFromField( L, -1, "workStreet" );
			const char *contactWorkCity = luaGetStringFromField( L, -1, "workCity" );
			const char *contactWorkState = luaGetStringFromField( L, -1, "workState" );
			const char *contactWorkZip = luaGetStringFromField( L, -1, "workZip" );
			const char *contactWorkCountry = luaGetStringFromField( L, -1, "workCountry" );
			// Social Profiles
			const char *contactSocialProfileFacebook = luaGetStringFromField( L, -1, "socialFacebook" );
			const char *contactSocialProfileTwitter = luaGetStringFromField( L, -1, "socialTwitter" );
			const char *contactSocialProfileFlickr = luaGetStringFromField( L, -1, "socialFlickr" );
			const char *contactSocialProfileLinkedIn = luaGetStringFromField( L, -1, "socialLinkedIn" );
			const char *contactSocialProfileMyspace = luaGetStringFromField( L, -1, "socialMyspace" );
			const char *contactSocialProfileSinaWeibo = luaGetStringFromField( L, -1, "socialSinaWeibo" );
			const char *contactSocialProfileGameCenter = luaGetStringFromField( L, -1, "socialGameCenter" );
			// Instant Messaging Profiles
			const char *contactInstantMessagingProfileAim = luaGetStringFromField( L, -1, "instantMessagingAim" );
			const char *contactInstantMessagingProfileFacebook = luaGetStringFromField( L, -1, "instantMessagingFacebook" );
			const char *contactInstantMessagingProfileGaduGadu = luaGetStringFromField( L, -1, "instantMessagingGaduGadu" );
			const char *contactInstantMessagingProfileGoogleTalk = luaGetStringFromField( L, -1, "instantMessagingGoogleTalk" );
			const char *contactInstantMessagingProfileICQ = luaGetStringFromField( L, -1, "instantMessagingICQ" );
			const char *contactInstantMessagingProfileJabber = luaGetStringFromField( L, -1, "instantMessagingJabber" );
			const char *contactInstantMessagingProfileMSN = luaGetStringFromField( L, -1, "instantMessagingMSN" );
			const char *contactInstantMessagingProfileQQ = luaGetStringFromField( L, -1, "instantMessagingQQ" );
			const char *contactInstantMessagingProfileSkype = luaGetStringFromField( L, -1, "instantMessagingSkype" );
			const char *contactInstantMessagingProfileYahoo = luaGetStringFromField( L, -1, "instantMessagingYahoo" );
			
			// Pop the data table
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
		}
	}

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
		NSNumber *propertiesPersonUrl = [[NSNumber alloc] initWithInt:(int)kABPersonURLProperty];
		NSNumber *propertiesPersonBirthday = [[NSNumber alloc] initWithInt:(int)kABPersonBirthdayProperty];
		NSNumber *propertiesPersonRelatedNames = [[NSNumber alloc] initWithInt:(int)kABPersonRelatedNamesProperty];
		NSNumber *propertiesPersonAddress = [[NSNumber alloc] initWithInt:(int)kABPersonAddressProperty];
		NSNumber *propertiesPersonSocialProfile = [[NSNumber alloc] initWithInt:(int)kABPersonSocialProfileProperty];
		NSNumber *propertiesPersonInstantMessagingProfile = [[NSNumber alloc] initWithInt:(int)kABPersonInstantMessageProperty];		

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
			else if ( 0 == strcmp( "urls", currentFilter ) )
			{
				[displayedItems addObject:propertiesPersonUrl];
			}
			else if ( 0 == strcmp( "birthday", currentFilter ) )
			{
				[displayedItems addObject:propertiesPersonBirthday];
			}
			else if ( 0  == strcmp( "relatedNames", currentFilter ) )
			{
				[displayedItems addObject:propertiesPersonRelatedNames];
			}
			else if ( 0 == strcmp( "address", currentFilter ) )
			{
				[displayedItems addObject:propertiesPersonAddress];
			}
			else if ( 0 == strcmp( "socialProfiles", currentFilter ) )
			{
				[displayedItems addObject:propertiesPersonSocialProfile];
			}
			else if ( 0 == strcmp( "instantMessagingProfiles", currentFilter ) )
			{
				[displayedItems addObject:propertiesPersonInstantMessagingProfile];
			}
		}

		// Set the pickers displayed properties to the displayedItems array.
		picker.displayedProperties = displayedItems;

		// Cleanup
		[propertiesPersonPhone release];
		[propertiesPersonEmail release];
		[propertiesPersonUrl release];
		[propertiesPersonBirthday release];
		[propertiesPersonRelatedNames release];
		[propertiesPersonSocialProfile release];
		[propertiesPersonInstantMessagingProfile release];
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
			
			// Pop the name field
			lua_pop( L, 1 );
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
			NSNumber *propertiesPersonUrl = [[NSNumber alloc] initWithInt:(int)kABPersonURLProperty];
			NSNumber *propertiesPersonBirthday = [[NSNumber alloc] initWithInt:(int)kABPersonBirthdayProperty];
			NSNumber *propertiesPersonRelatedNames = [[NSNumber alloc] initWithInt:(int)kABPersonRelatedNamesProperty];
			NSNumber *propertiesPersonAddress = [[NSNumber alloc] initWithInt:(int)kABPersonAddressProperty];
			NSNumber *propertiesPersonSocialProfile = [[NSNumber alloc] initWithInt:(int)kABPersonSocialProfileProperty];
			NSNumber *propertiesPersonInstantMessagingProfile = [[NSNumber alloc] initWithInt:(int)kABPersonInstantMessageProperty];
			
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
				else if ( 0 == strcmp( "urls", currentFilter ) )
				{
					[displayedItems addObject:propertiesPersonUrl];
				}
				else if ( 0 == strcmp( "birthday", currentFilter ) )
				{
					[displayedItems addObject:propertiesPersonBirthday];
				}
				else if ( 0  == strcmp( "relatedNames", currentFilter ) )
				{
					[displayedItems addObject:propertiesPersonRelatedNames];
				}
				else if ( 0 == strcmp( "address", currentFilter ) )
				{
					[displayedItems addObject:propertiesPersonAddress];
				}
				else if ( 0 == strcmp( "socialProfiles", currentFilter ) )
				{
					[displayedItems addObject:propertiesPersonSocialProfile];
				}
				else if ( 0 == strcmp( "instantMessagingProfiles", currentFilter ) )
				{
					[displayedItems addObject:propertiesPersonInstantMessagingProfile];
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
	const char *alternateName = NULL;
	const char *message = NULL;
	
	// Get the fields from lua
	if ( lua_istable( L, 2 ) )
	{
		alternateName = luaGetStringFromField( L, 2, "alternateName" );
		message = luaGetStringFromField( L, 2, "message" );
	}
		
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
	const char *popUpName = lua_tostring( L, 1 );

	if ( context && 0 == strcmp( "addressbook", popUpName ) )
	{
		Self& library = * context;
		
		// Create an instance of our delegate
		CoronaAddressBookDelegate *delegate = [[CoronaAddressBookDelegate alloc] init];
		
		// Assign our runtime view controller
		UIViewController *appViewController = library.GetAppViewController();
		
		// Assign the lua state so we can access it from within the delegate
		delegate.luaState = L;
		
		// Set the callback reference to MULL
		delegate.listenerRef = NULL;
		
		// Set reference to onComplete function
		if ( lua_istable( L, 2 ) )
		{
			// Get listener key
			lua_getfield( L, 2, "listener" );
			
			// Set the delegates listenerRef to reference the onComplete function (if it exists)
			if ( Lua::IsListener( L, -1, "addressBook" ) )
			{
				delegate.listenerRef = Lua::NewRef( L, -1 );
			}
			// Pop listener key
			lua_pop( L, 1 );
		}
		else
		{
			luaL_error( L, "The second argument to native.showPopup( 'addressbook' ) must be a table" );
		}
		
		// Initialize the display filters array
		delegate.contactDisplayFilters = [[NSMutableArray alloc] init];

		// Get the option key
		lua_getfield( L, 2, "option" );

		// Check the "name" parameter from lua
		const char *chosenAddressBookOption = lua_tostring( L, -1 );
		
		// Pop options key
		lua_pop( L, 1 );

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
		
		// Pop options table
		lua_pop( L, 1 );

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
	if ( NULL != self.listenerRef )
	{
		// Create the event
		Corona::Lua::NewEvent( self.luaState, "contact" );
		lua_pushstring( self.luaState, [self.chosenAddressBookOption UTF8String] );
		lua_setfield( self.luaState, -2, CoronaEventTypeKey() );

		// Create the events members
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
				
				// If the contact has a picture, save it to a file and tell lua where it is
				if ( ABPersonHasImageData( person ) )
				{
					NSData *contactPictureData = (NSData *)ABPersonCopyImageDataWithFormat(person, kABPersonImageFormatOriginalSize);
					UIImage *image = [UIImage imageWithData:contactPictureData];
					NSString *pictureFileDirectory = @"Documents";
					NSString *pictureFileName = @"contactPicture.png";
					NSString *pictureFilePath = nil;
					
					// Set the name of the contact picture file
					if ( contactFirstName && contactLastName )
					{
						pictureFileName = [NSString stringWithFormat:@"%s%s.png", [contactFirstName UTF8String], [contactLastName UTF8String] ];
					}
					if ( !contactFirstName && contactLastName )
					{
						pictureFileName = [NSString stringWithFormat:@"%s.png", [contactLastName UTF8String] ];
					}
					if ( ! contactFirstName && ! contactLastName && contactPhoneticFirstName && contactPhoneticLastName )
					{
						pictureFileName = [NSString stringWithFormat:@"%s%s.png", [contactPhoneticFirstName UTF8String], [contactPhoneticLastName UTF8String] ];
					}
					
					// Set the picture file path
					pictureFilePath = [NSString stringWithFormat:@"%@/%@", pictureFileDirectory, pictureFileName ];
					
					// Set the output path
					NSString *pngPath = [NSHomeDirectory() stringByAppendingPathComponent:pictureFilePath];
					
					// Write the image to a png file
					[UIImagePNGRepresentation(image) writeToFile:pngPath atomically:YES];
					
					// Create a table to store the picture data
					lua_newtable( self.luaState );
					
					// Set the filename
					lua_pushstring( self.luaState, [pictureFileName UTF8String] ); // Value
					lua_setfield( self.luaState, -2, "fileName" ); // Key
					
					// Set the base directory
					lua_getglobal( self.luaState, "system" );
					lua_getfield( self.luaState, -1, "DocumentsDirectory" );
					lua_setfield( self.luaState, -3, "baseDir" );
					lua_pop( self.luaState, 1 ); //Pop the system table
					
					// Set the "picture" table
					lua_setfield( self.luaState, -2, "picture" );
				}
				
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
					NSDate *anniversaryDate = (NSDate *)ABMultiValueCopyValueAtIndex(dates, j);
					NSString *dateValue = [NSDateFormatter localizedStringFromDate:anniversaryDate dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterNoStyle];
					NSString *dateKey = [NSString stringWithFormat:@"%s%d", "otherDate", j];

					if ( j == 0 ) dateKey = @"anniversary";
								
					lua_pushstring( self.luaState, [dateValue UTF8String] ); // Value
					lua_setfield( self.luaState, -2, [dateKey UTF8String] ); // Key
				}
			}

			// Set event.data
			lua_setfield( self.luaState, -2, "data" );
		}
		
		// Dispatch the event
		Corona::Lua::DispatchEvent( self.luaState, self.listenerRef, 1 );
				
		// Free native reference to listener
		Corona::Lua::DeleteRef( self.luaState, self.listenerRef );
		
		// Null the reference
		self.listenerRef = NULL;
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

