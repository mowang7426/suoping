#import <Foundation/Foundation.h>
#ifdef __cplusplus
#import "LSGCNotificationsAppBarPolicy.h"
#endif

// Main queue only except Configure, which marshals to main. No notification text IO.
void LSGCNotificationsAppBarConfigure(BOOL enabled);
void LSGCNotificationsAppBarLeaveLockScreen(void);
NSString *LSGCNotificationsAppBarDiagnostic(void);
#ifdef __cplusplus
BOOL LSGCNotificationsAppBarProviderABI(id controller, NSString **reason);
LSGCNotifications::Snapshot LSGCNotificationsAppBarReadSnapshot(id controller, NSString **reason);
#endif

// Foundation production bridge is also compiled unchanged by the macOS mock test.
@interface LSGCNotificationProjection : NSObject
@property(nonatomic,weak) id controller;
@property(nonatomic,readonly) NSUInteger hiddenCount;
@property(nonatomic,copy,readonly) NSString *selected;
@property(nonatomic,copy,readonly) NSString *reason;
- (instancetype)initWithController:(id)controller;
- (BOOL)selectApplication:(NSString *)application;
- (BOOL)reconcile; // bounded batch; YES means additional work remains
- (void)observeRequest:(id)request removed:(BOOL)removed;
- (void)observeSectionRemoved:(NSString *)identifier;
- (BOOL)restore;
- (void)sourceDestroyed;
- (NSArray<NSDictionary *> *)rows;
@end
