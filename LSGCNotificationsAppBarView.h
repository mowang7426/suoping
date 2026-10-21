#import <UIKit/UIKit.h>

// Detached UI component only. No native hook, no repository access, no installation.
// The coordinator must reserve real space BETWEEN native notification bottom and
// shortcut top before adding this view. An unverified provider must not add it.
@interface LSGCNotificationsAppBarView : UIView
@property(nonatomic,copy) void (^selectionRequested)(NSString *applicationIdentifier);
// Each row contains only { identifier, name, count }; @"" denotes All.
// Selection is supplied AFTER the native display adapter commits successfully.
- (void)renderRows:(NSArray<NSDictionary *> *)rows selected:(NSString *)identifier;
@end
