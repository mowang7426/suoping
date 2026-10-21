#import <Foundation/Foundation.h>
// Shared production discovery/ownership bridge; UIKit-free so mocks execute the
// exact selector, ABI and identity policy used by SpringBoard.
BOOL LSGCOwnerObjectGetter(id object, const char *selector, id *value);
BOOL LSGCOwnerVerified(id candidate, id combined, NSString **reason);
NSArray *LSGCDiscoverNotificationOwners(NSArray *roots, NSDictionary **diagnostic);
BOOL LSGCNotificationLockGate(id manager, NSString **diagnostic);
NSString *LSGCOwnerParentChain(id object);
