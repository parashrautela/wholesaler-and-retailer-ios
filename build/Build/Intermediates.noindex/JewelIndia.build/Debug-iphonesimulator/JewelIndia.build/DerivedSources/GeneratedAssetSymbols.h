#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"com.jewelindia.app";

/// The "AccentColor" asset catalog color resource.
static NSString * const ACColorNameAccentColor AC_SWIFT_PRIVATE = @"AccentColor";

/// The "LaunchBackground" asset catalog color resource.
static NSString * const ACColorNameLaunchBackground AC_SWIFT_PRIVATE = @"LaunchBackground";

/// The "JewelLogo" asset catalog image resource.
static NSString * const ACImageNameJewelLogo AC_SWIFT_PRIVATE = @"JewelLogo";

/// The "NavAddRetailer" asset catalog image resource.
static NSString * const ACImageNameNavAddRetailer AC_SWIFT_PRIVATE = @"NavAddRetailer";

/// The "NavCatalogue" asset catalog image resource.
static NSString * const ACImageNameNavCatalogue AC_SWIFT_PRIVATE = @"NavCatalogue";

/// The "NavChat" asset catalog image resource.
static NSString * const ACImageNameNavChat AC_SWIFT_PRIVATE = @"NavChat";

/// The "NavHome" asset catalog image resource.
static NSString * const ACImageNameNavHome AC_SWIFT_PRIVATE = @"NavHome";

/// The "NavOrders" asset catalog image resource.
static NSString * const ACImageNameNavOrders AC_SWIFT_PRIVATE = @"NavOrders";

/// The "NavUpload" asset catalog image resource.
static NSString * const ACImageNameNavUpload AC_SWIFT_PRIVATE = @"NavUpload";

#undef AC_SWIFT_PRIVATE
