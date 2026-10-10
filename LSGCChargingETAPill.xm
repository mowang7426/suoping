#import "LSGCChargingETAPill.h"
#import <objc/runtime.h>
#import <objc/message.h>

static NSString *const LSGCDomain = @"com.minis.lockscreengradientclock";
static __weak UIView *LSGCPillHost;
static __weak UIView *LSGCPill;
static NSString *LSGCLastText;
static BOOL LSGCRefreshing;
static BOOL LSGCHooksInstalled;
static NSMutableSet *LSGCHookedContainers;

/*
 * ETA is intentionally a closed-world reader.  The class families below are
 * the only names observed/mentioned for SpringBoard's battery implementation
 * in the investigation (SBUIBattery..., SBBattery..., BUICharging...,
 * BatteryData).  A level, UIDevice, or an arbitrary object is never used.
 * Selectors are queried dynamically and every returned value passes the
 * source/key/unit/range gates.  This is a candidate reader, not a claim that
 * iOS 17.0 exports one of these fields on every device.
 */
typedef struct { BOOL charging; BOOL reliable; NSInteger minutes; BOOL full; } LSGCETAResult;
static BOOL LSGCEtaSourceName(NSString *n) {
    return [n hasPrefix:@"SBUIBattery"] || [n hasPrefix:@"SBBattery"] ||
           [n hasPrefix:@"BUICharging"] || [n isEqualToString:@"BatteryData"];
}
static id LSGCSafeValue(id object, NSString *key) {
    if (!object || !key) return nil;
    @try { return [object valueForKey:key]; } @catch (__unused NSException *e) { return nil; }
}
static id LSGCSafeCall(id object, SEL sel) {
    if (!object || !sel || ![object respondsToSelector:sel]) return nil;
    @try { return ((id(*)(id,SEL))objc_msgSend)(object,sel); } @catch (__unused NSException *e) { return nil; }
}
static BOOL LSGCMinutesFromValue(id value, BOOL seconds, NSInteger *out) {
    if (!value || !out) return NO;
    double d=0;
    if ([value isKindOfClass:NSNumber.class]) d=[value doubleValue];
    else if ([value isKindOfClass:NSString.class]) {
        NSString *s=[(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSScanner *sc=[NSScanner scannerWithString:s]; if (![sc scanDouble:&d] || !sc.isAtEnd) return NO;
    } else return NO;
    if (!isfinite(d) || d<0 || d>24.0*60.0*60.0) return NO;
    NSInteger m=seconds ? (NSInteger)ceil(d/60.0) : (NSInteger)llround(d);
    if (m<=0 || m>24*60) return NO;
    *out=m; return YES;
}
static LSGCETAResult LSGCReadPrivateETA(void) {
    LSGCETAResult bad={NO,NO,0,NO};
    /* No class/selector is linked: absence is a normal iOS 15/17 fallback. */
    NSArray *classNames=@[@"SBUIBattery",@"SBUIBatteryData",@"SBBattery",@"SBBatteryData",@"BUICharging",@"BUIChargingData",@"BatteryData"];
    NSArray *accessors=@[@"sharedInstance",@"sharedBatteryData",@"batteryData",@"defaultInstance"];
    NSArray *minuteKeys=@[@"estimatedTimeRemainingMinutes",@"chargingTimeRemainingMinutes"];
    NSArray *secondKeys=@[@"estimatedTimeRemaining",@"chargingTimeRemaining",@"batteryTimeRemaining"];
    for (NSString *cn in classNames) {
        Class cls=NSClassFromString(cn); if (!cls || !LSGCEtaSourceName(cn)) continue;
        id source=nil;
        for (NSString *a in accessors) { source=LSGCSafeCall((id)cls,NSSelectorFromString(a)); if (source) break; }
        if (!source) source=(id)cls; // class object may itself expose a data key
        for (NSString *key in minuteKeys) { NSInteger m=0; if (LSGCMinutesFromValue(LSGCSafeValue(source,key),NO,&m)) { LSGCETAResult r={YES,YES,m,NO}; return r; } }
        for (NSString *key in secondKeys) { NSInteger m=0; if (LSGCMinutesFromValue(LSGCSafeValue(source,key),YES,&m)) { LSGCETAResult r={YES,YES,m,NO}; return r; } }
        /* Only parse text from a battery ETA-named field, never arbitrary UI. */
        for (NSString *key in @[@"estimatedTimeRemainingString",@"chargingTimeRemainingString"]) {
            id v=LSGCSafeValue(source,key); if (![v isKindOfClass:NSString.class]) continue;
            NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:@"([0-9]{1,4})\\s*(?:min|minute|分钟)" options:NSRegularExpressionCaseInsensitive error:NULL];
            NSTextCheckingResult *x=[re firstMatchInString:v options:0 range:NSMakeRange(0,[(NSString *)v length])];
            if (x) { NSInteger m=[[(NSString *)v substringWithRange:[x rangeAtIndex:1]] integerValue]; if (m>0&&m<=1440) { LSGCETAResult r={YES,YES,m,NO}; return r; } }
        }
    }
    return bad;
}

NSString *LSGCChargingETAText(BOOL charging, BOOL reliable, NSInteger minutes, BOOL full) {
    if (!charging) return nil;
    if (full) return @"已充满";
    if (reliable && minutes > 0 && minutes <= 24 * 60) return [NSString stringWithFormat:@"预计还需 %ld 分钟充满", (long)minutes];
    return @"正在充电";
}
static BOOL LSGCOn(void) { CFPreferencesAppSynchronize((__bridge CFStringRef)LSGCDomain); id v=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("chargingETAPill"),(__bridge CFStringRef)LSGCDomain)); return [v respondsToSelector:@selector(boolValue)]&&[v boolValue]; }

static BOOL LSGCClassChainHas(Class cls, NSArray *names) {
    for (Class c=cls;c;c=class_getSuperclass(c)) {
        NSString *n=NSStringFromClass(c);
        for (NSString *wanted in names) if ([n isEqualToString:wanted]) return YES;
    }
    return NO;
}
static BOOL LSGCLockContainer(UIView *v) {
    return v && v.window && LSGCClassChainHas(v.class,@[@"CSQuickActionsView",@"SBUILockScreenQuickActionsView",@"CSCombinedListView"]);
}
static NSString *LSGCButtonWords(UIView *v) {
    NSMutableString *s=[NSMutableString string];
    for (NSString *x in @[v.accessibilityIdentifier ?: @"",v.accessibilityLabel ?: @""]) [s appendFormat:@" %@",x];
    if ([v isKindOfClass:UIButton.class]) {
        UIButton *c=(UIButton *)v;
        if (c.currentTitle) [s appendFormat:@" %@",c.currentTitle];
        for (NSNumber *state in @[@(UIControlStateNormal),@(UIControlStateHighlighted),@(UIControlStateSelected)]) {
                UIImage *im=[c imageForState:state.unsignedIntegerValue];
                if (im) [s appendFormat:@" %@",im.description ?: @""];
        }
    }
    return s.lowercaseString;
}
static NSInteger LSGCSemantic(UIView *v) {
    if (![v isKindOfClass:UIControl.class]) return 0;
    NSString *s=LSGCButtonWords(v);
    BOOL flash=[s containsString:@"flash"]||[s containsString:@"torch"]||[s containsString:@"手电"]||[s containsString:@"闪光"];
    BOOL camera=[s containsString:@"camera"]||[s containsString:@"相机"];
    return flash==camera ? 0 : (flash ? 1 : 2);
}
static void LSGCFindButtons(UIView *v, UIView **flash, UIView **camera, NSUInteger *flashCount, NSUInteger *cameraCount) {
    if (!v) return;
    if ([v isKindOfClass:UIControl.class] && (LSGCClassChainHas(v.class,@[@"SBUILockScreenQuickActionButton",@"CSQuickActionButton"]) || LSGCSemantic(v))) {
        NSInteger kind=LSGCSemantic(v);
        if (kind==1) { (*flashCount)++; if (*flashCount==1) *flash=v; }
        if (kind==2) { (*cameraCount)++; if (*cameraCount==1) *camera=v; }
    }
    for (UIView *x in v.subviews) LSGCFindButtons(x,flash,camera,flashCount,cameraCount);
}
static UIView *LSGCCommonHost(UIView *a, UIView *b) {
    for (UIView *x=a;x;x=x.superview) for (UIView *y=b;y;y=y.superview) if (x==y) return x;
    return nil;
}
static void LSGCRemove(void) { [LSGCPill removeFromSuperview]; LSGCPill=nil; LSGCPillHost=nil; LSGCLastText=nil; }
static NSArray<UIWindow *> *LSGCWindows(void) {
    NSMutableArray *r=[NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) if ([scene isKindOfClass:UIWindowScene.class]) [r addObjectsFromArray:((UIWindowScene *)scene).windows];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [r addObjectsFromArray:UIApplication.sharedApplication.windows];
#pragma clang diagnostic pop
    return r;
}
static void LSGCCollectContainers(UIView *v, NSMutableArray *out) {
    if (!v) return;
    if (LSGCLockContainer(v)) [out addObject:v];
    for (UIView *x in v.subviews) LSGCCollectContainers(x,out);
}
static void LSGCRefreshSoon(void) { dispatch_async(dispatch_get_main_queue(), ^{ LSGCChargingETAPillRefresh(); }); }
static void LSGCHookContainerClass(Class cls) {
    if (!cls || !LSGCClassChainHas(cls,@[@"CSQuickActionsView",@"SBUILockScreenQuickActionsView",@"CSCombinedListView"])) return;
    if (!LSGCHookedContainers) LSGCHookedContainers=[NSMutableSet set];
    NSString *key=NSStringFromClass(cls); if ([LSGCHookedContainers containsObject:key]) return;
    [LSGCHookedContainers addObject:key];
    for (NSString *selName in @[@"layoutSubviews",@"didMoveToWindow"]) {
        SEL sel=NSSelectorFromString(selName); Method m=class_getInstanceMethod(cls,sel); if (!m) continue;
        IMP old=method_getImplementation(m);
        if ([selName isEqualToString:@"layoutSubviews"]) {
            void (^block)(UIView *)=^(UIView *self){ ((void(*)(id,SEL))old)(self,sel); LSGCRefreshSoon(); };
            class_replaceMethod(cls,sel,imp_implementationWithBlock(block),method_getTypeEncoding(m));
        } else {
            void (^block)(UIView *,UIWindow *)=^(UIView *self,UIWindow *window){ ((void(*)(id,SEL,UIWindow *))old)(self,sel,window); LSGCRefreshSoon(); };
            class_replaceMethod(cls,sel,imp_implementationWithBlock(block),method_getTypeEncoding(m));
        }
    }
}
static void LSGCInstallContainerHooks(void) {
    if (LSGCHooksInstalled) return; LSGCHooksInstalled=YES;
    /* Event-driven only: no timer/display link/polling. UIDevice is used for
     * state-change notification, never for ETA or percentage estimation. */
    UIDevice.currentDevice.batteryMonitoringEnabled=YES;
    [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceBatteryStateDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *n){ LSGCChargingETAPillRefresh(); }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *n){ LSGCChargingETAPillRefresh(); }];
    for (NSString *n in @[@"CSQuickActionsView",@"SBUILockScreenQuickActionsView",@"CSCombinedListView"]) LSGCHookContainerClass(NSClassFromString(n));
}
void LSGCChargingETAPillClear(void) { dispatch_async(dispatch_get_main_queue(), ^{ LSGCRemove(); }); }
void LSGCChargingETAPillRefresh(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (LSGCRefreshing) return; LSGCRefreshing=YES; LSGCInstallContainerHooks();
        @autoreleasepool {
            if (!LSGCOn()) { LSGCRemove(); LSGCRefreshing=NO; return; }
            UIDevice *d=UIDevice.currentDevice;
            BOOL charging=d.batteryState==UIDeviceBatteryStateCharging||d.batteryState==UIDeviceBatteryStateFull;
            BOOL full=d.batteryState==UIDeviceBatteryStateFull;
            LSGCETAResult eta=LSGCReadPrivateETA();
            /* UIDevice supplies state only; it is never used to calculate ETA. */
            if (eta.reliable) { charging=YES; full=NO; }
            NSString *text=LSGCChargingETAText(charging,eta.reliable,eta.minutes,full); if (!text) { LSGCRemove(); LSGCRefreshing=NO; return; }
            for (UIWindow *w in LSGCWindows()) {
                NSMutableArray *containers=[NSMutableArray array]; for (UIView *root in w.subviews) LSGCCollectContainers(root,containers);
                for (UIView *container in containers) {
                    LSGCHookContainerClass(container.class); UIView *f=nil,*c=nil; NSUInteger nf=0,nc=0; LSGCFindButtons(container,&f,&c,&nf,&nc);
                    /* Ambiguous or duplicate semantics are deliberately rejected. */
                    if (nf!=1||nc!=1||!f||!c) continue;
                    NSLog(@"[LSGC][ChargingPill] semantic evidence container=%@ flash=%@/%@ camera=%@/%@",NSStringFromClass(container.class),NSStringFromClass(f.class),LSGCButtonWords(f),NSStringFromClass(c.class),LSGCButtonWords(c));
                    UIView *host=LSGCCommonHost(f,c); if (!host) continue;
                    CGRect fr=[f.superview convertRect:f.frame toView:host],cr=[c.superview convertRect:c.frame toView:host];
                    if (CGRectGetMaxX(fr)>=CGRectGetMinX(cr)||fabs(CGRectGetMidY(fr)-CGRectGetMidY(cr))>1.0) continue;
                    CGFloat gap=CGRectGetMinX(cr)-CGRectGetMaxX(fr); if (gap<8) continue;
                    CGFloat width=MIN(220.0,MAX(100.0,gap-8)),height=30; CGRect r=CGRectMake(CGRectGetMaxX(fr)+(gap-width)/2,CGRectGetMidY(fr)-height/2,width,height);
                    if (CGRectIntersectsRect(r,fr)||CGRectIntersectsRect(r,cr)) continue;
                    if (LSGCPillHost!=host) { LSGCRemove(); LSGCPillHost=host; }
                    if (!LSGCPill) { UIView *pill=[[UIView alloc] initWithFrame:r]; pill.backgroundColor=[UIColor colorWithWhite:0 alpha:.42]; pill.layer.cornerRadius=15; pill.userInteractionEnabled=NO; UIImageView *bolt=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"bolt.fill"]]; bolt.tintColor=UIColor.whiteColor; bolt.frame=CGRectMake(8,7,16,16); [pill addSubview:bolt]; UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(27,0,width-31,height)]; label.tag=7001; label.textColor=UIColor.whiteColor; label.font=[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold]; label.adjustsFontSizeToFitWidth=YES; label.minimumScaleFactor=.7; label.textAlignment=NSTextAlignmentCenter; [pill addSubview:label]; [host addSubview:pill]; LSGCPill=pill; }
                    LSGCPill.frame=r; UILabel *label=(UILabel *)[LSGCPill viewWithTag:7001]; if (![LSGCLastText isEqualToString:text]) { LSGCLastText=[text copy]; label.text=text; } LSGCRefreshing=NO; return;
                }
            }
            LSGCRemove();
        }
        LSGCRefreshing=NO;
    });
}
