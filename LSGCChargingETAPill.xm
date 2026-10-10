#import "LSGCChargingETAPill.h"
#import <objc/runtime.h>

static NSString *const LSGCDomain = @"com.minis.lockscreengradientclock";
static __weak UIView *LSGCPillHost;
static __weak UIView *LSGCPill;
static NSString *LSGCLastText;
static BOOL LSGCRefreshing;

NSString *LSGCChargingETAText(BOOL charging, BOOL reliable, NSInteger minutes, BOOL full) {
    if (!charging) return nil;
    if (full) return @"已充满";
    if (reliable && minutes > 0 && minutes <= 24 * 60) return [NSString stringWithFormat:@"预计还需 %ld 分钟充满", (long)minutes];
    return @"正在充电";
}
static BOOL LSGCOn(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)LSGCDomain);
    id v=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("chargingETAPill"), (__bridge CFStringRef)LSGCDomain));
    return [v respondsToSelector:@selector(boolValue)] && [v boolValue];
}
static BOOL LSGCClass(UIView *v, NSArray *names) {
    if (!v) return NO;
    NSString *n=NSStringFromClass(v.class);
    for (NSString *wanted in names) if ([n isEqualToString:wanted]) return YES;
    return NO;
}
static BOOL LSGCLockContainer(UIView *v) {
    return LSGCClass(v,@[@"CSQuickActionsView",@"SBUILockScreenQuickActionsView",@"CSCombinedListView"]) && v.window != nil;
}
static UIButton *LSGCButton(UIView *v, BOOL left) {
    if (!LSGCClass(v,@[@"SBUILockScreenQuickActionButton",@"CSQuickActionButton"])) return nil;
    NSString *a=v.accessibilityIdentifier.lowercaseString ?: @"";
    NSString *l=v.accessibilityLabel.lowercaseString ?: @"";
    BOOL flashlight=[a containsString:@"flash"]||[l containsString:@"flash"]||[l containsString:@"手电"];
    BOOL camera=[a containsString:@"camera"]||[l containsString:@"camera"]||[l containsString:@"相机"];
    if (left) return flashlight ? (UIButton *)v : nil;
    return camera ? (UIButton *)v : nil;
}
static void LSGCFind(UIView *v, UIButton **flash, UIButton **camera) {
    if (!v || !LSGCLockContainer(v)) return;
    for (UIView *x in v.subviews) {
        UIButton *b=LSGCButton(x,YES); if (b) *flash=b;
        b=LSGCButton(x,NO); if (b) *camera=b;
        LSGCFind(x,flash,camera);
    }
}
static UIView *LSGCCommonHost(UIView *a, UIView *b) {
    for (UIView *x=a;x;x=x.superview) for (UIView *y=b;y;y=y.superview) if (x==y) return x;
    return nil;
}
static NSArray<UIWindow *> *LSGCWindows(void) {
    NSMutableArray<UIWindow *> *result=[NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        [result addObjectsFromArray:((UIWindowScene *)scene).windows];
    }
    return result;
}
void LSGCChargingETAPillClear(void) { dispatch_async(dispatch_get_main_queue(), ^{ LSGCRemove(); }); }
void LSGCChargingETAPillRefresh(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (LSGCRefreshing) return; LSGCRefreshing=YES;
        @autoreleasepool {
            if (!LSGCOn()) { LSGCRemove(); LSGCRefreshing=NO; return; }
            UIDevice *d=UIDevice.currentDevice; BOOL charging=(d.batteryState==UIDeviceBatteryStateCharging || d.batteryState==UIDeviceBatteryStateFull);
            BOOL full=d.batteryState==UIDeviceBatteryStateFull;
            // UIDevice has no ETA. Do not infer minutes from level or elapsed time.
            NSString *text=LSGCChargingETAText(charging,NO,0,full);
            if (!text) { LSGCRemove(); LSGCRefreshing=NO; return; }
            for (UIWindow *w in LSGCWindows()) {
                __block UIButton *f=nil,*c=nil;
                for (UIView *root in w.subviews) LSGCFind(root,&f,&c);
                if (!f||!c) continue;
                UIView *host=LSGCCommonHost(f,c); if (!host) continue;
                CGRect fr=[f.superview convertRect:f.frame toView:host], cr=[c.superview convertRect:c.frame toView:host];
                if (CGRectGetMaxX(fr)>=CGRectGetMinX(cr) || CGRectGetMidY(fr)!=CGRectGetMidY(cr)) continue;
                CGFloat gap=CGRectGetMinX(cr)-CGRectGetMaxX(fr); if (gap<8) continue;
                CGFloat width=MIN(220.0,MAX(100.0,gap-8)); CGFloat height=30;
                CGRect r=CGRectMake(CGRectGetMaxX(fr)+(gap-width)/2,CGRectGetMidY(fr)-height/2,width,height);
                if (CGRectIntersectsRect(r,fr)||CGRectIntersectsRect(r,cr)) continue;
                if (LSGCPillHost!=host) { LSGCRemove(); LSGCPillHost=host; }
                if (!LSGCPill) {
                    UIView *pill=[[UIView alloc] initWithFrame:r]; pill.backgroundColor=[UIColor colorWithWhite:0 alpha:.42]; pill.layer.cornerRadius=15; pill.userInteractionEnabled=NO;
                    UIImageView *bolt=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"bolt.fill"]]; bolt.tintColor=UIColor.whiteColor; bolt.frame=CGRectMake(8,7,16,16); [pill addSubview:bolt];
                    UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(27,0,width-31,height)]; label.tag=7001; label.textColor=UIColor.whiteColor; label.font=[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold]; label.adjustsFontSizeToFitWidth=YES; label.minimumScaleFactor=.7; label.textAlignment=NSTextAlignmentCenter; [pill addSubview:label]; [host addSubview:pill]; LSGCPill=pill;
                }
                LSGCPill.frame=r; UILabel *label=(UILabel *)[LSGCPill viewWithTag:7001];
                if (![LSGCLastText isEqualToString:text]) { LSGCLastText=[text copy]; label.text=text; }
                LSGCRefreshing=NO; return;
            }
            LSGCRemove();
        }
        LSGCRefreshing=NO;
    });
}
