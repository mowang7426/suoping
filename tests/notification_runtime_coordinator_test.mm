// UIKit is a narrow test double; the included coordinator and linked ownership
// and projection bridges are the actual production sources, not copied policies.
#import <UIKit/UIKit.h>
#import "../LSGCNotificationsAppBar.h"
#import "../LSGCNotificationsAppBarView.h"
#include <cassert>
#include <iostream>
@implementation UIView
- (instancetype)init { return [self initWithFrame:CGRectZero]; }
- (instancetype)initWithFrame:(CGRect)frame { if ((self=[super init])) { _frame=frame; _bounds=CGRectMake(0,0,frame.size.width,frame.size.height); _alpha=1; _transform=CGAffineTransformIdentity; _subviews=[NSMutableArray array]; } return self; }
- (void)setFrame:(CGRect)frame { _frame=frame; _bounds.size=frame.size; }
- (UIWindow *)window { if ([self isKindOfClass:UIWindow.class]) return (UIWindow *)self; return self.superview.window; }
- (CGSize)intrinsicContentSize { return CGSizeMake(240,52); }
- (void)addSubview:(UIView *)view { [view removeFromSuperview]; [self.subviews addObject:view]; view.superview=self; }
- (void)removeFromSuperview { [self.superview.subviews removeObjectIdenticalTo:self]; self.superview=nil; }
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view {
    for (UIView *v=self;v && v!=self.window;v=v.superview) { rect.origin.x+=v.frame.origin.x; rect.origin.y+=v.frame.origin.y; }
    for (UIView *v=view;v && v!=view.window;v=v.superview) { rect.origin.x-=v.frame.origin.x; rect.origin.y-=v.frame.origin.y; }
    return rect;
}
@end
@implementation UIScrollView @end
@interface NCNotificationListView : UIScrollView @end
@implementation NCNotificationListView @end
@implementation UIViewController
- (BOOL)isViewLoaded { return self.view!=nil; }
@end
@implementation UIWindow @end
@implementation UIApplication
+ (instancetype)sharedApplication { static UIApplication *app; if (!app) app=[UIApplication new]; return app; }
@end
@implementation UIFont
+ (instancetype)preferredFontForTextStyle:(NSString *)style { (void)style; return [UIFont new]; }
- (CGFloat)lineHeight { return 18; }
@end
@implementation LSGCNotificationsAppBarView
- (void)renderRows:(NSArray *)rows selected:(NSString *)selected { (void)rows; (void)selected; }
@end
@interface SBCoverSheetWindow : UIWindow @end
@implementation SBCoverSheetWindow @end
@interface NCNotificationListCell : UIView @end
@implementation NCNotificationListCell @end
@interface CSQuickActionsView : UIView
@property(nonatomic,strong) UIView *flashlightButton,*cameraButton;
@end
@implementation CSQuickActionsView @end
@interface NCNotificationRequest : NSObject
@property(nonatomic,copy) NSString *sectionIdentifier,*notificationIdentifier;
@end
@implementation NCNotificationRequest
- (id)content { assert(false && "notification body access"); return nil; }
@end
@interface NCNotificationStructuredSectionList : NSObject
@property(nonatomic,strong) NSMutableArray *items;
@property(nonatomic,readonly) NSArray *allNotificationRequests;
@end
@implementation NCNotificationStructuredSectionList
- (NSArray *)allNotificationRequests { return self.items.copy; }
@end
@interface NCNotificationMasterList : NSObject
@property(nonatomic,copy) NSArray *notificationListSections;
@end
@implementation NCNotificationMasterList @end
@interface NCNotificationStructuredListViewController : UIViewController
@property(nonatomic,strong) id masterList;
@property(nonatomic,strong) NCNotificationListView *masterListView;
- (void)insertNotificationRequest:(id)request;
- (void)modifyNotificationRequest:(id)request;
- (void)removeNotificationRequest:(id)request;
@end
@implementation NCNotificationStructuredListViewController
- (void)insertNotificationRequest:(id)request { NSMutableArray *items=[(NCNotificationStructuredSectionList *)[self.masterList notificationListSections][0] items]; if (![items containsObject:request]) [items addObject:request]; }
- (void)modifyNotificationRequest:(id)request { (void)request; }
- (void)removeNotificationRequest:(id)request { [[[self.masterList notificationListSections][0] items] removeObjectIdenticalTo:request]; }
@end
@interface CSCombinedListViewController : UIViewController
@property(nonatomic,strong) UIViewController *notificationListViewController;
@end
@implementation CSCombinedListViewController @end
@interface SBLockScreenManager : NSObject
@property(nonatomic,strong) UIViewController *coverSheetViewController;
@property(nonatomic) bool locked,visible,passcode,overlay;
+ (instancetype)sharedInstance;
@end
@implementation SBLockScreenManager
+ (instancetype)sharedInstance { static SBLockScreenManager *value; if (!value) value=[SBLockScreenManager new]; return value; }
- (bool)isUILocked { return self.locked; }
- (bool)isLockScreenVisible { return self.visible; }
- (bool)_isPasscodeVisible { return self.passcode; }
- (bool)isPasscodeEntryTransientOverlayVisible { return self.overlay; }
@end
#import <mach-o/dyld.h>
// Suppress only automatic image-loader registration; tests invoke the real
// original-first callbacks and coordinator explicitly on the main thread.
#define _dyld_register_func_for_add_image(fn) ((void)(fn))
#import "../LSGCNotificationsAppBarRuntime.mm"
#undef _dyld_register_func_for_add_image
static unsigned originalCalls=0;
static void NoOp(id o,SEL s) { (void)o; (void)s; ++originalCalls; }
static void NoOpAnimated(id o,SEL s,bool a) { (void)a; NoOp(o,s); }
static void NativeInsert(id o,SEL s,id r) { (void)s; ++originalCalls; [o insertNotificationRequest:r]; }
static void NativeRemove(id o,SEL s,id r) { (void)s; ++originalCalls; [o removeNotificationRequest:r]; }
static void NativeWithdraw(id o,SEL s,id r) { NativeRemove(o,s,r); }
static void NativeBacklight(id o,SEL s,id controller,long long state,long long source) { (void)controller; (void)state; (void)source; NoOp(o,s); }
static unsigned insetCalls=0;
static void NativeInsetOriginal(id o,SEL s,UIEdgeInsets value) { (void)s; ++insetCalls; [(UIScrollView *)o setContentInset:value]; }
static void NativeLocked(id o,SEL s,bool value) { (void)s; ++originalCalls; [o setLocked:value]; }
// Drain one already-scheduled production turn deterministically; no wall clock
// timer and no replacement of Configure/Discover/Attach/Pump/callback logic.
static void Tick() { queued=NO; Pump(); }
static NCNotificationRequest *Request(NSString *app,NSString *key) {
    auto *r=[NCNotificationRequest new]; r.sectionIdentifier=app; r.notificationIdentifier=key; return r;
}
int main() { @autoreleasepool {
    assert(NSThread.isMainThread);
    installed=YES; // Installation/OS availability is separately compiled for iOS.
    insetHookReady=YES; origNativeInsets=NativeInsetOriginal;
    origLayout=NoOp; origAppear=NoOpAnimated; origDisappear=NoOpAnimated;
    origQuickLayout=NoOp; origCombinedAppear=NoOpAnimated;
    origInsert=NativeInsert; origRemove=NativeRemove; origModify=NativeInsert;
    origWithdraw=NativeWithdraw; origDispatcherWithdraw=NativeWithdraw;
    origSetLocked=NativeLocked; origDestroy=NoOp; origBacklight=NativeBacklight;
    auto *manager=[SBLockScreenManager sharedInstance]; manager.locked=true; manager.visible=true;
    auto *window=[[SBCoverSheetWindow alloc] initWithFrame:CGRectMake(0,0,430,932)];
    auto *host=[CSCombinedListViewController new]; host.view=[[UIView alloc] initWithFrame:window.bounds];
    window.rootViewController=host; [window addSubview:host.view];
    auto *list=[NCNotificationStructuredListViewController new];
    list.parentViewController=host; host.childViewControllers=@[list]; host.notificationListViewController=list;
    list.view=[[UIView alloc] initWithFrame:CGRectMake(0,0,430,810)]; [host.view addSubview:list.view];
    auto *cell=[[NCNotificationListCell alloc] initWithFrame:CGRectMake(12,400,400,250)]; [list.view addSubview:cell];
    auto *actions=[[CSQuickActionsView alloc] initWithFrame:CGRectMake(0,780,430,140)];
    actions.flashlightButton=[[UIView alloc] initWithFrame:CGRectMake(20,40,60,60)];
    actions.cameraButton=[[UIView alloc] initWithFrame:CGRectMake(350,40,60,60)];
    [actions addSubview:actions.flashlightButton]; [actions addSubview:actions.cameraButton]; [host.view addSubview:actions];
    auto *section=[NCNotificationStructuredSectionList new];
    auto *a=Request(@"app.a",@"a1"),*b=Request(@"app.b",@"b1");
    section.items=[NSMutableArray arrayWithArray:@[a,b]];
    auto *master=[NCNotificationMasterList new]; master.notificationListSections=@[section]; list.masterList=master;
    manager.coverSheetViewController=host; UIApplication.sharedApplication.windows=@[window];
    assert(!enabled && !candidate && !owner && !projection);
    LSGCNotificationsAppBarConfigure(YES);
    assert(queued && !owner); // enable must not synchronously scan/apply
    Tick();
    assert(owner==list && projection && bar.superview==window);
    assert([status isEqual:@"native-display-projection"] && [providerDiagnostic isEqual:@"ready"]);
    assert([projection selectApplication:@"app.a"]); Tick();
    assert(projection.hiddenCount==1 && ![section.items containsObject:b]);
    // Native source arrives after filtering: exercise actual original-first hook.
    auto *c=Request(@"app.b",@"b2"); unsigned before=originalCalls;
    Insert(list,sel_registerName("insertNotificationRequest:"),c); assert(originalCalls==before+1); Tick();
    assert(projection.hiddenCount==2 && ![section.items containsObject:c]);
    DispatcherWithdraw(list,sel_registerName("withdrawNotificationWithRequest:"),b); Tick();
    LSGCNotificationsAppBarConfigure(NO); Tick();
    assert(!bar && !projection && ![section.items containsObject:b] && [section.items containsObject:c]);
    // Already-existing source is found again, no new didAppear is necessary.
    candidate=nil; LSGCNotificationsAppBarConfigure(YES); Tick(); assert(owner==list && bar);
    // Unlock samples are normal: restore and do not mount. Relock hook discovers
    // the old live source with no dependency on another list appear callback.
    SetLocked(manager,sel_registerName("_setUILocked:"),false); Tick(); assert(!bar && !projection);
    SetLocked(manager,sel_registerName("_setUILocked:"),true); Tick(); assert(projection && bar);
    manager.passcode=true; Tick(); assert(!bar);
    manager.passcode=false; CombinedAppear(host,sel_registerName("viewDidAppear:"),true); Tick(); assert(bar);
    // Bright-screen transition discovers a pre-existing source even when the
    // system did not issue another list/Combined appear or layout callback.
    manager.visible=false; Tick(); assert(!bar && !projection);
    manager.visible=true; before=originalCalls;
    Backlight(manager,sel_registerName("backlightController:didTransitionToBacklightState:source:"),nil,2,3);
    assert(originalCalls==before+1); Tick(); assert(owner==list && bar);
    // Old/unrelated class callback must not steal ownership from explicit getter.
    auto *unrelated=[NCNotificationStructuredListViewController new]; unrelated.view=list.view;
    unrelated.parentViewController=host; unrelated.masterList=master;
    Layout(unrelated,sel_registerName("viewDidLayoutSubviews")); Tick(); assert(owner==list);
    before=originalCalls; Appear(list,sel_registerName("viewDidAppear:"),true); Tick(); assert(originalCalls==before+1 && owner==list);
    Disappear(list,sel_registerName("viewDidDisappear:"),true); Tick(); assert(!bar);
    Appear(list,sel_registerName("viewDidAppear:"),true); Tick(); assert(bar);
    // Real production Geometry and mount path: no spare pixels is not success.
    cell.frame=CGRectMake(12,0,400,800); Tick();
    assert(!bar && [status isEqual:@"safe-layout-space-unavailable"]);
    assert([layoutDiagnostic containsString:@"reservation-unverified-native-scroll"] && [layoutDiagnostic containsString:@"bottom=800.00"]);
    // The real production reservation path is identity-gated to masterListView.
    // Full lists get a genuinely shorter native viewport, not an overlay that
    // simply covers cells. Existing content remains native-scroll reachable.
    auto *scroll=[[NCNotificationListView alloc] initWithFrame:CGRectMake(0,0,430,810)];
    scroll.translatesAutoresizingMaskIntoConstraints=YES; scroll.clipsToBounds=YES;
    [list.view addSubview:scroll]; [scroll addSubview:cell]; list.masterListView=scroll;
    Tick(); assert(bar && reservedScroll==scroll && reservedBottom>0);
    CGFloat contribution=reservedBottom;
    assert(scroll.frame.size.height<810 && scroll.contentInset.bottom==contribution);
    assert(CGRectGetMaxY(scroll.frame)+8<=CGRectGetMinY(bar.frame));
    Tick(); assert(scroll.contentInset.bottom==contribution && reservedBottom==contribution);
    UIEdgeInsets external=scroll.contentInset; external.bottom=7; external.top=19;
    unsigned insetBefore=insetCalls;
    NativeInsets(scroll,@selector(setContentInset:),external); // real external absolute setter callback
    assert(insetCalls==insetBefore+1);
    auto *other=[UIScrollView new]; NativeInsets(other,@selector(setContentInset:),external);
    assert(other.contentInset.bottom==7); // never alter an unrelated instance
    Tick(); assert(scroll.contentInset.bottom==contribution+7);
    external.bottom=150; NativeInsets(scroll,@selector(setContentInset:),external);
    Tick(); assert(scroll.contentInset.bottom==contribution+150);
    external.bottom=7; NativeInsets(scroll,@selector(setContentInset:),external);
    LSGCNotificationsAppBarConfigure(NO); Tick();
    assert(scroll.contentInset.bottom==7 && scroll.contentInset.top==19 && scroll.frame.size.height==810 && !reservedScroll);
    LSGCNotificationsAppBarConfigure(YES); Tick(); assert(bar && reservedScroll==scroll);
    // An external/native frame update is newer authority: do not stale-write
    // the pre-reservation historical frame when disabling.
    CGRect systemFrame=scroll.frame; systemFrame.size.height=700; scroll.frame=systemFrame;
    LSGCNotificationsAppBarConfigure(NO); Tick(); assert(scroll.frame.size.height==700 && scroll.contentInset.bottom==7);
    // Unknown/autolayout scroll containers fail closed rather than mutate them.
    scroll.translatesAutoresizingMaskIntoConstraints=NO;
    LSGCNotificationsAppBarConfigure(YES); Tick(); assert(!bar && !reservedScroll);
    scroll.translatesAutoresizingMaskIntoConstraints=YES;
    scroll.frame=CGRectMake(0,0,430,810);
    scroll.transform=CGAffineTransformMakeScale(0.9,0.9); Tick(); assert(!bar && !reservedScroll);
    scroll.transform=CGAffineTransformIdentity;
    insetHookReady=NO; Tick(); assert(!bar && !reservedScroll && [layoutDiagnostic containsString:@"insetHook=0"]);
    insetHookReady=YES;
    cell.frame=CGRectMake(12,400,400,250); Tick(); assert(bar);
    // Window migration is local: detach old overlay, attach to current window.
    auto *newWindow=[[SBCoverSheetWindow alloc] initWithFrame:window.bounds];
    [newWindow addSubview:host.view]; newWindow.rootViewController=host;
    UIApplication.sharedApplication.windows=@[newWindow]; Tick(); assert(bar.superview==newWindow);
    // A source in any random window is rejected even with the correct parent.
    LSGCNotificationsAppBarConfigure(NO); Tick();
    auto *wrongWindow=[[UIWindow alloc] initWithFrame:window.bounds]; [wrongWindow addSubview:host.view];
    LSGCNotificationsAppBarConfigure(YES); Tick(); assert(!projection && !bar);
    assert([status isEqual:@"candidate-window-not-cover-sheet"]);
    NSString *lockedFailure=lastAttachFailure;
    manager.locked=false; QuickLayout(actions,sel_registerName("layoutSubviews")); Tick();
    assert([lastAttachFailure isEqual:lockedFailure]); // settings/unlocked sample must retain evidence
    manager.locked=true;
    [newWindow addSubview:host.view]; QuickLayout(actions,sel_registerName("layoutSubviews")); Tick(); assert(bar);
    // A newly-owned source must restore the previous owner's real hidden rows
    // before moving ownership, even when no fresh appear callback is delivered.
    assert([projection selectApplication:@"app.a"]); Tick(); assert(projection.hiddenCount==1);
    auto *successor=[NCNotificationStructuredListViewController new]; successor.view=list.view; successor.parentViewController=host;
    auto *successorSection=[NCNotificationStructuredSectionList new]; successorSection.items=[NSMutableArray arrayWithArray:@[Request(@"app.a",@"a2"),Request(@"app.d",@"d1")]];
    auto *successorMaster=[NCNotificationMasterList new]; successorMaster.notificationListSections=@[successorSection]; successor.masterList=successorMaster;
    host.childViewControllers=@[successor]; host.notificationListViewController=successor;
    Layout(successor,sel_registerName("viewDidLayoutSubviews")); Tick(); Tick();
    assert(owner==successor && projection && [section.items containsObject:c] && ![section.items containsObject:b]);
    host.childViewControllers=@[list]; host.notificationListViewController=list;
    Layout(list,sel_registerName("viewDidLayoutSubviews")); Tick(); assert(owner==list && projection);
    // ABI changes must fail closed and be distinguishable from empty rows.
    LSGCNotificationsAppBarConfigure(NO); Tick(); list.masterList=[NSObject new];
    LSGCNotificationsAppBarConfigure(YES); Tick();
    assert(!projection && [status isEqual:@"runtime-provider-abi-mismatch"] && [providerDiagnostic isEqual:@"master-list-abi-mismatch"]);
    list.masterList=master; QuickLayout(actions,sel_registerName("layoutSubviews")); Tick(); assert(projection);
    assert([projection selectApplication:@"app.a"]); Tick(); assert(projection.hiddenCount==1);
    Destroy(list,sel_registerName("dealloc")); assert(!projection && !bar && !ownerIdentity);
    std::cout << "PASS production UIKit coordinator (mock UI only): async enable existing-source discovery, original-first arrival/withdrawal, disable restoration/no resurrection, unlock/relock/passcode/backlight retry, old/unrelated and new callbacks, real Geometry/mount unknown-scroll refusal and validated full-list viewport reservation, idempotent additive insets, latest external inset/frame restoration, autolayout refusal, overlay window migration, wrong-window/provider-ABI rejection, source-destroyed cleanup\n";
} return 0; }
