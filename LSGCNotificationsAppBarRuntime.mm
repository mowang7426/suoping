#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import "LSGCNotificationsAppBar.h"
#import "LSGCNotificationOwnerDiscovery.h"
#include "LSGCNotificationOwnerPolicy.h"
#import "LSGCNotificationsAppBarView.h"
#include <cstring>
#include <atomic>
static std::atomic<bool> installQueued{false};

extern unsigned LSGCNotificationProjectionDepth;
namespace {
static BOOL enabled=NO,queued=NO,pumping=NO,installed=NO,leaving=NO,interactionPaused=NO;
static __weak UIViewController *owner;
static __weak UIViewController *candidate;
static void *ownerIdentity=nullptr;
static unsigned recoveryFailures=0;
static __weak UIView *quick;
static LSGCNotificationProjection *projection;
static LSGCNotificationsAppBarView *bar;
static NSString *status=@"disabled";
static NSString *lockDiagnostic=@"not-sampled", *attachDiagnostic=@"not-attempted", *providerDiagnostic=@"not-sampled", *snapshotDiagnostic=@"not-sampled", *layoutDiagnostic=@"not-sampled", *hookDiagnostic=@"not-sampled";
static NSDictionary *discoveryDiagnostic;
static BOOL discoveryPending=NO, discovering=NO;
static unsigned discoveryRuns=0, windowCount=0, viewNodes=0;
static void Discover();
static void Attach(id controller,NSArray *roots);
static void RequestDiscovery();
static NSArray *lastRows;
static NSString *lastSelection;
static void Schedule();
static void FlushPersistence();
static __weak id presentationMaster;
static BOOL persistenceDeferred=NO;
static id Get(id o,const char *s) { return ((id(*)(id,SEL))objc_msgSend)(o,sel_registerName(s)); }
static BOOL Signature(Class cls,const char *name,char result,const char *args) {
    Method m=class_getInstanceMethod(cls,sel_registerName(name));
    if (!m || method_getNumberOfArguments(m)!=strlen(args)+2) return NO;
    auto match=[](const char *s,char c) { while (s && *s && strchr("rnNoORV",*s)) ++s; return s && *s==c; };
    char *t=method_copyReturnType(m); BOOL ok=match(t,result); free(t);
    for (unsigned i=0;ok && i<strlen(args);++i) { t=method_copyArgumentType(m,i+2); ok=match(t,args[i]); free(t); }
    return ok;
}
static id LockManager() {
    Class cls=objc_getClass("SBLockScreenManager");
    return Signature(object_getClass(cls),"sharedInstance",'@',"")?Get(cls,"sharedInstance"):nil;
}
static BOOL Locked() {
    id manager=LockManager();
    BOOL result=LSGCNotificationLockGate(manager,&lockDiagnostic);
    lockDiagnostic=[NSString stringWithFormat:@"manager=%@ sharedInstance=%@ %@",NSStringFromClass([manager class]),manager?@"available":@"missing-or-ABI",lockDiagnostic];
    return result;
}
static BOOL Shown(UIView *view,UIWindow *window) {
    if (!view || view.window!=window || CGRectIsEmpty(view.bounds)) return NO;
    unsigned depth=0;
    for (UIView *v=view;v;v=v.superview) if (++depth>64 || v.hidden || v.alpha<0.02) return NO;
    return YES;
}
static void Unmount() {
    [bar removeFromSuperview]; bar=nil; lastRows=nil; lastSelection=nil;
}
// Bounded local hierarchy walk, no label/body scans, no screen-size guesses.
static BOOL Geometry(CGRect *result) {
    UIViewController *controller=owner; UIView *actions=quick;
    UIView *native=controller.isViewLoaded?controller.view:nil;
    UIWindow *window=native.window;
    layoutDiagnostic=[NSString stringWithFormat:@"owner=%@ nativeWindow=%@ quick=%@ quickWindow=%@ nativeFrame=%@ quickFrame=%@",NSStringFromClass(controller.class),NSStringFromClass(window.class),NSStringFromClass(actions.class),NSStringFromClass(actions.window.class),NSStringFromCGRect(native.frame),NSStringFromCGRect(actions.frame)];
    if (!window || !Shown(native,window) || !Shown(actions,window)) { layoutDiagnostic=[layoutDiagnostic stringByAppendingString:@" failure=owner-or-quick-offscreen/window-mismatch"]; return NO; }
    if (!Signature(object_getClass(actions),"flashlightButton",'@',"") ||
        !Signature(object_getClass(actions),"cameraButton",'@',"")) { layoutDiagnostic=[layoutDiagnostic stringByAppendingString:@" failure=quick-action-getter-ABI"]; return NO; }
    UIView *flash=Get(actions,"flashlightButton"),*camera=Get(actions,"cameraButton");
    if (![flash isKindOfClass:UIView.class] || ![camera isKindOfClass:UIView.class] ||
        !Shown(flash,window) || !Shown(camera,window)) { layoutDiagnostic=[layoutDiagnostic stringByAppendingString:@" failure=shortcut-offscreen"]; return NO; }
    CGRect f=[flash convertRect:flash.bounds toView:window],c=[camera convertRect:camera.bounds toView:window];
    CGFloat ceiling=MIN(CGRectGetMinY(f),CGRectGetMinY(c))-8;
    NSMutableArray<UIView *> *todo=[NSMutableArray arrayWithObject:native];
    CGFloat bottom=-CGFLOAT_MAX;
    Class cell=objc_getClass("NCNotificationListCell");
    for (NSUInteger i=0;i<todo.count;i++) {
        if (todo.count>1024) { layoutDiagnostic=[layoutDiagnostic stringByAppendingString:@" failure=cell-node-budget"]; return NO; }
        UIView *v=todo[i];
        if (Shown(v,window) && [v isKindOfClass:cell]) {
            CGRect r=[v convertRect:v.bounds toView:window];
            if (CGRectIntersectsRect(r,window.bounds)) bottom=MAX(bottom,CGRectGetMaxY(r));
        }
        if (v!=bar) { if (todo.count+v.subviews.count>1024) { layoutDiagnostic=[layoutDiagnostic stringByAppendingString:@" failure=local-view-budget"]; return NO; } [todo addObjectsFromArray:v.subviews]; }
    }
    if (bottom==-CGFLOAT_MAX) { layoutDiagnostic=[layoutDiagnostic stringByAppendingString:@" failure=no-visible-native-cell"]; return NO; }
    // Our charging pill is in the shortcut host. Its own identifier is stable;
    // do not inspect notification text, icon accessibility text, or other labels.
    todo=[NSMutableArray arrayWithObject:actions.superview?:actions];
    for (NSUInteger i=0;i<todo.count;i++) {
        if (todo.count>512) { layoutDiagnostic=[layoutDiagnostic stringByAppendingString:@" failure=shortcut-node-budget"]; return NO; }
        UIView *v=todo[i];
        if ([v.accessibilityIdentifier isEqual:@"LSGCChargingETAPill"] && Shown(v,window)) {
            CGRect r=[v convertRect:v.bounds toView:window]; ceiling=MIN(ceiling,CGRectGetMinY(r)-8);
        }
        if (v!=bar) { if (todo.count+v.subviews.count>1024) { layoutDiagnostic=[layoutDiagnostic stringByAppendingString:@" failure=local-view-budget"]; return NO; } [todo addObjectsFromArray:v.subviews]; }
    }
    CGFloat height=bar?bar.intrinsicContentSize.height:MAX(44,ceil([UIFont preferredFontForTextStyle:UIFontTextStyleCaption1].lineHeight*2+16));
    CGRect nativeRect=[native convertRect:native.bounds toView:window];
    CGFloat left=MAX(CGRectGetMinX(nativeRect),window.safeAreaInsets.left)+12;
    CGFloat right=MIN(CGRectGetMaxX(nativeRect),CGRectGetWidth(window.bounds)-window.safeAreaInsets.right)-12;
    layoutDiagnostic=[layoutDiagnostic stringByAppendingFormat:@" nativeRect=%@ flashlight=%@ camera=%@ bottom=%.2f ceiling=%.2f available=%.2f required=%.2f width=%.2f",NSStringFromCGRect(nativeRect),NSStringFromCGRect(f),NSStringFromCGRect(c),bottom,ceiling,ceiling-bottom-8,height,right-left];
    if (!LSGCNotificationOwner::GapFits(bottom,ceiling,right-left,height)) { layoutDiagnostic=[layoutDiagnostic stringByAppendingString:@" failure=insufficient-gap-no-validated-reservation"]; return NO; }
    *result=CGRectMake(left,ceiling-height,right-left,height);
    return CGRectContainsRect(window.bounds,*result) && !CGRectIntersectsRect(*result,f) && !CGRectIntersectsRect(*result,c);
}
static void Pump() {
    if (pumping) return;
    pumping=YES;
    @try {
        if (enabled && discoveryPending && !discovering) { discoveryPending=NO; Discover(); }
        if (!installed) { Unmount(); if (!enabled) status=@"disabled"; return; }
        if (!projection) { Unmount(); if (!enabled) status=@"disabled"; else if ([status isEqual:@"runtime-adapter-ready"] || [status isEqual:@"disabled"]) status=@"waiting-native-owner"; return; }
        if (!owner) { [projection sourceDestroyed]; projection=nil; Unmount(); status=@"source-destroyed"; return; }
        BOOL locked=Locked();
        if (!enabled || leaving || interactionPaused || !locked) {
            BOOL more=[projection restore]; FlushPersistence(); Unmount(); status=projection.hiddenCount?@"restore-pending":(!enabled?@"disabled-restored":(!locked?@"lock-gate-closed-wait-lifecycle":@"lifecycle-paused-restored"));
            if (more) Schedule();
            else if (!projection.hiddenCount) projection=nil;
            return;
        }
        if (!owner.isViewLoaded || !owner.view.window || !Shown(owner.view,owner.view.window)) {
            BOOL more=[projection restore]; FlushPersistence(); Unmount(); status=@"owner-offscreen-wait-lifecycle";
            if (more) Schedule(); return;
        }
        if (bar.superview && bar.superview!=owner.view.window) Unmount();
        LSGCNotificationsAppBarReadSnapshot(owner,&snapshotDiagnostic);
        CGRect frame;
        if (!Geometry(&frame)) {
            BOOL more=[projection restore]; FlushPersistence(); Unmount(); status=@"safe-layout-space-unavailable";
            if (more) Schedule(); return;
        }
        BOOL more=[projection reconcile];
        snapshotDiagnostic=projection.reason;
        FlushPersistence();
        recoveryFailures=0;
        if (more) { Schedule(); return; }
        if (![projection.reason isEqual:@"ready"]) { status=projection.reason; Unmount(); return; }
        NSArray *rows=[projection rows];
        if (rows.count<2) { Unmount(); status=@"no-active-notifications"; return; }
        if (rows.count>129) {
            BOOL pending=[projection restore]; FlushPersistence(); Unmount(); status=@"application-budget-exceeded";
            if (pending) Schedule(); return;
        }
        if (!bar) {
            bar=[[LSGCNotificationsAppBarView alloc] initWithFrame:frame];
            bar.translatesAutoresizingMaskIntoConstraints=YES;
            bar.selectionRequested=^(NSString *app) { if ([projection selectApplication:app]) Schedule(); };
            [owner.view.window addSubview:bar];
        }
        if (!CGRectEqualToRect(bar.frame,frame)) bar.frame=frame;
        if (![lastRows isEqual:rows] || ![lastSelection isEqual:projection.selected]) {
            [bar renderRows:rows selected:projection.selected]; lastRows=rows; lastSelection=projection.selected;
        }
        status=@"native-display-projection";
    } @catch (__unused NSException *e) {
        status=@"coordinator-exception"; leaving=YES; Unmount();
        if (++recoveryFailures<=2) Schedule(); // never self-schedule an infinite exception loop
    }
    @finally { pumping=NO; }
}
static void Schedule() {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(),^{ Schedule(); }); return; }
    if (queued) return;
    queued=YES;
    dispatch_async(dispatch_get_main_queue(),^{ queued=NO; Pump(); });
}
static void Attach(id controller,NSArray *roots) {
    if (!NSThread.isMainThread || !enabled || leaving || ![controller isKindOfClass:UIViewController.class]) return;
    candidate=controller;
    attachDiagnostic=[NSString stringWithFormat:@"candidate=%@ parents=%@",NSStringFromClass([controller class]),LSGCOwnerParentChain(controller)];
    if (!Locked()) { status=@"lock-gate-closed-wait-lifecycle"; return; }
    if (![controller isViewLoaded] || ![controller view].window) { status=@"candidate-offscreen-wait-lifecycle"; return; }
    NSDictionary *diag=nil;
    // Reuse production identity policy even for lifecycle candidates. This does
    // not trust a callback, a class name or a lock-screen ancestor by itself.
    NSArray *verified=LSGCDiscoverNotificationOwners(roots,&diag);
    attachDiagnostic=[attachDiagnostic stringByAppendingFormat:@" ownership=%@",diag[@"ownership"]];
    if (![verified containsObject:controller]) { status=@"unverified-cover-sheet-owner"; return; }
    if (owner && owner!=controller) {
        if (projection.hiddenCount) { status=@"owner-switch-restore-pending"; [projection restore]; FlushPersistence(); return; }
        projection=nil; Unmount(); presentationMaster=nil;
    }
    if (!LSGCNotificationsAppBarProviderABI(controller,&providerDiagnostic)) { status=@"runtime-provider-abi-mismatch"; return; }
    owner=controller; ownerIdentity=(__bridge void *)controller;
    presentationMaster=Get(controller,"masterList");
    if (!projection) projection=[[LSGCNotificationProjection alloc] initWithController:controller];
    status=@"owner-bound";
}
static void RequestDiscovery() {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(),^{ RequestDiscovery(); }); return; }
    if (!enabled || pumping || discovering) return;
    discoveryPending=YES; Schedule();
}
static void Discover() {
    if (discovering || !enabled || !installed) return;
    discovering=YES; ++discoveryRuns; windowCount=0; viewNodes=0;
    @try {
        NSMutableArray *roots=[NSMutableArray array];
        id cover=nil; LSGCOwnerObjectGetter(LockManager(),"coverSheetViewController",&cover);
        if ([cover isKindOfClass:UIViewController.class]) [roots addObject:cover];
        // Do not scan arbitrary application windows, scenes or UILabels.
        Class coverWindow=objc_getClass("SBCoverSheetWindow");
        for (UIWindow *w in UIApplication.sharedApplication.windows) {
            if (windowCount>=8) break;
            if (!coverWindow || ![w isKindOfClass:coverWindow]) continue;
            ++windowCount; if (w.rootViewController) [roots addObject:w.rootViewController];
            [roots addObject:w];
        }
        if (candidate) [roots addObject:candidate];
        discoveryDiagnostic=nil;
        NSArray *found=LSGCDiscoverNotificationOwners(roots,&discoveryDiagnostic);
        // Discover an already-created shortcut host too. Limited to the loaded
        // cover-sheet tree; no global hooks, text reads or view loading.
        UIView *coverView=[cover isViewLoaded]?[cover view]:nil;
        NSMutableArray *views=[NSMutableArray array];
        if (coverView) [views addObject:coverView];
        for (UIViewController *c in roots) if ([c isKindOfClass:UIViewController.class] && c.isViewLoaded && c.view.window && views.count<1024) [views addObject:c.view];
        Class quickClass=objc_getClass("CSQuickActionsView");
        for (NSUInteger i=0;i<views.count && i<1024;++i) {
            UIView *v=views[i]; ++viewNodes;
            if (quickClass && [v isKindOfClass:quickClass]) quick=v;
            if (views.count+v.subviews.count<=1024) [views addObjectsFromArray:v.subviews];
        }
        status=@"discovery-no-verified-owner";
        for (id c in found) { Attach(c,roots); if (owner==c && projection) break; }
        if (!Locked() && !projection) status=@"lock-gate-closed-wait-lifecycle";
    } @catch (__unused NSException *e) { status=@"discovery-exception"; }
    @finally { discovering=NO; }
}
static void Observe(id request,BOOL removed) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(),^{ Observe(request,removed); }); return; }
    if (!enabled && !projection.hiddenCount) return;
    [projection observeRequest:request removed:removed]; Schedule();
}
static void (*origCombinedAppear)(id,SEL,bool);
static void CombinedAppear(id self,SEL cmd,bool animated) {
    origCombinedAppear(self,cmd,animated); leaving=NO; RequestDiscovery();
}
static void (*origLayout)(id,SEL);
static void (*origAppear)(id,SEL,bool);
static void (*origDisappear)(id,SEL,bool);
static void (*origQuickLayout)(id,SEL);
static void (*origInsert)(id,SEL,id);
static void (*origModify)(id,SEL,id);
static void (*origRemove)(id,SEL,id);
static void (*origPost)(id,SEL,id);
static void (*origUpdate)(id,SEL,id);
static void (*origWithdraw)(id,SEL,id);
static void (*origDispatcherWithdraw)(id,SEL,id);
static void (*origSectionRemove)(id,SEL,id);
static void SectionRemove(id self,SEL cmd,id identifier) {
    origSectionRemove(self,cmd,identifier);
    void (^observe)(void)=^{ [projection observeSectionRemoved:identifier]; if (enabled || projection.hiddenCount) Schedule(); };
    if (NSThread.isMainThread) observe(); else dispatch_async(dispatch_get_main_queue(),observe);
}
static void (*origSetLocked)(id,SEL,bool);
static void (*origPasscode)(id,SEL,bool,bool);
static void Passcode(id self,SEL cmd,bool visible,bool animated) {
    origPasscode(self,cmd,visible,animated);
    if (!visible) { leaving=NO; RequestDiscovery(); }
    if (NSThread.isMainThread && visible) Unmount();
    Schedule();
}
static void (*origInteractionBegin)(id,SEL,id,id);
static void (*origInteractionEnd)(id,SEL,id,id);
static void InteractionBegin(id self,SEL cmd,id list,id card) {
    origInteractionBegin(self,cmd,list,card);
    if (list==owner) { interactionPaused=YES; Schedule(); }
}
static void InteractionEnd(id self,SEL cmd,id list,id card) {
    origInteractionEnd(self,cmd,list,card);
    if (list==owner) { interactionPaused=NO; RequestDiscovery(); }
}
static void (*origPersist)(id,SEL);
static void (*origDestroy)(__unsafe_unretained id,SEL);
static void Destroy(__unsafe_unretained id self,SEL cmd) {
    void *identity=(__bridge void *)self;
    BOOL ours=(identity==ownerIdentity);
    origDestroy(self,cmd); // lifecycle original first; never send to a deallocated owner
    if (!ours) return;
    void (^cleanup)(void)=^{
        if (ownerIdentity!=identity) return;
        [projection sourceDestroyed]; projection=nil; ownerIdentity=nullptr;
        presentationMaster=nil; persistenceDeferred=NO; interactionPaused=NO; Unmount(); status=@"source-destroyed";
    };
    if (NSThread.isMainThread) cleanup(); else dispatch_async(dispatch_get_main_queue(),cleanup);
}
static void Persist(id self,SEL cmd) {
    if (self==presentationMaster && (LSGCNotificationProjectionDepth || projection.hiddenCount)) {
        persistenceDeferred=YES; return;
    }
    origPersist(self,cmd);
}
static void FlushPersistence() {
    if (persistenceDeferred && !projection.hiddenCount && presentationMaster) {
        persistenceDeferred=NO;
        origPersist(presentationMaster,sel_registerName("_updateNotificationListPersistentState"));
    }
}
static void Layout(id self,SEL cmd) {
    origLayout(self,cmd);
    candidate=self;
    RequestDiscovery();
}
static void Appear(id self,SEL cmd,bool animated) {
    origAppear(self,cmd,animated); candidate=self; leaving=NO; RequestDiscovery();
}
static void Disappear(id self,SEL cmd,bool animated) {
    origDisappear(self,cmd,animated);
    if (self==owner) { leaving=YES; Schedule(); }
}
static void QuickLayout(id self,SEL cmd) {
    origQuickLayout(self,cmd); quick=self;
    RequestDiscovery();
}
static void Insert(id self,SEL cmd,id request) {
    origInsert(self,cmd,request);
    if (!LSGCNotificationProjectionDepth && self==owner) Observe(request,NO);
}
static void Modify(id self,SEL cmd,id request) {
    origModify(self,cmd,request);
    if (!LSGCNotificationProjectionDepth && self==owner) Observe(request,NO);
}
static void Remove(id self,SEL cmd,id request) {
    origRemove(self,cmd,request);
    if (!LSGCNotificationProjectionDepth && self==owner) Observe(request,YES);
}
static void Post(id self,SEL cmd,id request) { origPost(self,cmd,request); RequestDiscovery(); }
static void Update(id self,SEL cmd,id request) { origUpdate(self,cmd,request); RequestDiscovery(); }
static void Withdraw(id self,SEL cmd,id request) { origWithdraw(self,cmd,request); Observe(request,YES); }
static void DispatcherWithdraw(id self,SEL cmd,id request) { origDispatcherWithdraw(self,cmd,request); Observe(request,YES); }
static void SetLocked(id self,SEL cmd,bool locked) {
    origSetLocked(self,cmd,locked);
    if (!locked) LSGCNotificationsAppBarLeaveLockScreen();
    else { leaving=NO; RequestDiscovery(); }
}
struct Hook { const char *cls,*selector; char result; const char *args; IMP replacement; IMP *original; };
static void Install() {
    if (installed) return;
    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion!=17) { status=@"unsupported-os"; return; }
    Hook hooks[]={
        {"NCNotificationStructuredListViewController","dealloc",'v',"",(IMP)Destroy,(IMP *)&origDestroy},
        {"NCNotificationStructuredListViewController","viewDidLayoutSubviews",'v',"",(IMP)Layout,(IMP *)&origLayout},
        {"NCNotificationStructuredListViewController","viewDidAppear:",'v',"B",(IMP)Appear,(IMP *)&origAppear},
        {"NCNotificationStructuredListViewController","viewDidDisappear:",'v',"B",(IMP)Disappear,(IMP *)&origDisappear},
        {"NCNotificationStructuredListViewController","insertNotificationRequest:",'v',"@",(IMP)Insert,(IMP *)&origInsert},
        {"NCNotificationStructuredListViewController","modifyNotificationRequest:",'v',"@",(IMP)Modify,(IMP *)&origModify},
        {"NCNotificationStructuredListViewController","removeNotificationRequest:",'v',"@",(IMP)Remove,(IMP *)&origRemove},
        {"NCNotificationMasterList","_updateNotificationListPersistentState",'v',"",(IMP)Persist,(IMP *)&origPersist},
        {"CSQuickActionsView","layoutSubviews",'v',"",(IMP)QuickLayout,(IMP *)&origQuickLayout},
        {"CSCombinedListViewController","notificationStructuredListViewController:didBeginUserInteractionWithViewController:",'v',"@@",(IMP)InteractionBegin,(IMP *)&origInteractionBegin},
        {"CSCombinedListViewController","notificationStructuredListViewController:didEndUserInteractionWithViewController:",'v',"@@",(IMP)InteractionEnd,(IMP *)&origInteractionEnd},
        {"CSCombinedListViewController","postNotificationRequest:",'v',"@",(IMP)Post,(IMP *)&origPost},
        {"CSCombinedListViewController","updateNotificationRequest:",'v',"@",(IMP)Update,(IMP *)&origUpdate},
        {"CSCombinedListViewController","withdrawNotificationRequest:",'v',"@",(IMP)Withdraw,(IMP *)&origWithdraw},
        {"NCNotificationDispatcher","removeNotificationSectionWithIdentifier:",'v',"@",(IMP)SectionRemove,(IMP *)&origSectionRemove},
        {"NCNotificationDispatcher","withdrawNotificationWithRequest:",'v',"@",(IMP)DispatcherWithdraw,(IMP *)&origDispatcherWithdraw},
        {"SBLockScreenManager","setPasscodeVisible:animated:",'v',"BB",(IMP)Passcode,(IMP *)&origPasscode},
        {"SBLockScreenManager","_setUILocked:",'v',"B",(IMP)SetLocked,(IMP *)&origSetLocked},
    };
    // Validate the WHOLE surface before hooking ANY method. Unknown iOS17
    // runtime shape remains off; no fake-success flag and no invented selector.
    for (const Hook &h:hooks) if (!Signature(objc_getClass(h.cls),h.selector,h.result,h.args)) {
        hookDiagnostic=[NSString stringWithFormat:@"%s/%s",h.cls,h.selector]; status=@"runtime-hook-abi-unavailable"; return;
    }
    installed=YES;
    // Optional narrow lifecycle wake trigger; no global UIView interception.
    Class combined=objc_getClass("CSCombinedListViewController");
    if (Signature(combined,"viewDidAppear:",'v',"B")) MSHookMessageEx(combined,sel_registerName("viewDidAppear:"),(IMP)CombinedAppear,(IMP *)&origCombinedAppear);
    for (const Hook &h:hooks) MSHookMessageEx(objc_getClass(h.cls),sel_registerName(h.selector),h.replacement,h.original);
    hookDiagnostic=@"all-required-signatures-valid";
    status=@"runtime-adapter-ready";
}
static void ImageLoaded(const struct mach_header *,intptr_t) {
    if (installQueued.exchange(true)) return;
    dispatch_async(dispatch_get_main_queue(),^{ installQueued=false; Install(); });
}
}
void LSGCNotificationsAppBarConfigure(BOOL value) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(),^{ LSGCNotificationsAppBarConfigure(value); }); return; }
    enabled=value;
    if (value) { Install(); leaving=NO; recoveryFailures=0; if (installed) RequestDiscovery(); }
    Schedule();
}
void LSGCNotificationsAppBarLeaveLockScreen(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(),^{ LSGCNotificationsAppBarLeaveLockScreen(); }); return; }
    leaving=YES; Schedule();
}
NSString *LSGCNotificationsAppBarDiagnostic(void) {
    if (!NSThread.isMainThread) return @"NotificationsAppBar reason=not-main-thread";
    NSArray *rows=[projection rows];
    NSUInteger total=[rows.firstObject[@"count"] unsignedIntegerValue];
    BOOL applied=bar.superview && [status isEqual:@"native-display-projection"] &&
        [projection.reason isEqual:@"ready"] && [lastSelection isEqual:projection.selected] && projection.selected.length>0;
    return [NSString stringWithFormat:@"NotificationsAppBar enabled=%d adapter=%d mounted=%d applied=%d selected=%@ total=%lu apps=%lu hidden=%lu reason=%@ targetDeviceVerified=0\nownerDiscovery runs=%u windows=%u viewNodes=%u detail=%@\nattach=%@\nlocked=%@\nproviderABI=%@ snapshot=%@ hookABI=%@\nlayout=%@",
        enabled,installed,bar.superview!=nil,applied,projection.selected.length?@"app":@"all",(unsigned long)total,
        (unsigned long)(rows.count?rows.count-1:0),(unsigned long)projection.hiddenCount,status,discoveryRuns,windowCount,viewNodes,discoveryDiagnostic,attachDiagnostic,lockDiagnostic,providerDiagnostic,snapshotDiagnostic,hookDiagnostic,layoutDiagnostic];
}
__attribute__((constructor)) static void NotificationsAppBarInitialize() {
    _dyld_register_func_for_add_image(ImageLoaded);
}
