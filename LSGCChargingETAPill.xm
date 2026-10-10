#import "LSGCChargingETAPill.h"
#import <objc/runtime.h>

static NSString *const LSGCDomain = @"com.minis.lockscreengradientclock";
static __weak UIView *LSGCPillHost;
static __weak UIView *LSGCPill;
static NSString *LSGCLastText;
static BOOL LSGCRefreshing;
static BOOL LSGCHooksInstalled;
static NSMutableSet *LSGCHookedContainers;

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
/* iOS 17 changed the concrete classes. Match the complete class chain, never
 * every UIButton/UIControl in SpringBoard. */
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
    for (NSString *n in @[@"CSQuickActionsView",@"SBUILockScreenQuickActionsView",@"CSCombinedListView"]) LSGCHookContainerClass(NSClassFromString(n));
}
void LSGCChargingETAPillClear(void) { dispatch_async(dispatch_get_main_queue(), ^{ LSGCRemove(); }); }
void LSGCChargingETAPillRefresh(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (LSGCRefreshing) return; LSGCRefreshing=YES; LSGCInstallContainerHooks();
        @autoreleasepool {
            if (!LSGCOn()) { LSGCRemove(); LSGCRefreshing=NO; return; }
            UIDevice *d=UIDevice.currentDevice; BOOL charging=d.batteryState==UIDeviceBatteryStateCharging||d.batteryState==UIDeviceBatteryStateFull; BOOL full=d.batteryState==UIDeviceBatteryStateFull;
            NSString *text=LSGCChargingETAText(charging,NO,0,full); if (!text) { LSGCRemove(); LSGCRefreshing=NO; return; }
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
