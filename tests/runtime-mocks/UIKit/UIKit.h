#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dispatch/dispatch.h>
typedef struct { CGFloat top,left,bottom,right; } UIEdgeInsets;
@class UIWindow;
@interface UIView : NSObject
@property(nonatomic) CGRect frame,bounds;
@property(nonatomic) BOOL hidden,translatesAutoresizingMaskIntoConstraints;
@property(nonatomic) CGFloat alpha;
@property(nonatomic,weak) UIView *superview;
@property(nonatomic,strong) NSMutableArray<UIView *> *subviews;
@property(nonatomic,copy) NSString *accessibilityIdentifier;
@property(nonatomic,readonly) UIWindow *window;
@property(nonatomic,readonly) CGSize intrinsicContentSize;
- (instancetype)initWithFrame:(CGRect)frame;
- (void)addSubview:(UIView *)view;
- (void)removeFromSuperview;
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view;
@end
@interface UIViewController : NSObject
@property(nonatomic,strong) UIView *view;
@property(nonatomic,readonly) BOOL isViewLoaded;
@property(nonatomic,weak) UIViewController *parentViewController;
@property(nonatomic,copy) NSArray *childViewControllers;
@property(nonatomic,strong) UIViewController *presentedViewController;
@property(nonatomic,weak) id nextResponder;
@end
@interface UIWindow : UIView
@property(nonatomic,strong) UIViewController *rootViewController;
@property(nonatomic) UIEdgeInsets safeAreaInsets;
@end
@interface UIApplication : NSObject
@property(nonatomic,copy) NSArray *windows;
+ (instancetype)sharedApplication;
@end
@interface UIFont : NSObject
@property(nonatomic,readonly) CGFloat lineHeight;
+ (instancetype)preferredFontForTextStyle:(NSString *)style;
@end
static NSString * const UIFontTextStyleCaption1=@"caption";
static inline NSString *NSStringFromCGRect(CGRect r) { return [NSString stringWithFormat:@"{{%.2f, %.2f}, {%.2f, %.2f}}",r.origin.x,r.origin.y,r.size.width,r.size.height]; }
