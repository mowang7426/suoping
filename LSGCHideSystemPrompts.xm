#import "LSGCHideSystemPrompts.h"
#import <objc/runtime.h>
#import <objc/message.h>

static const void *LSGCPromptStateKey=&LSGCPromptStateKey;
static BOOL LSGCPromptInstalled;
static NSMutableSet *LSGCPromptObjects;

@interface LSGCPromptState : NSObject
@property(nonatomic,weak) UIView *view;
@property(nonatomic) CGFloat alpha;
@property(nonatomic) BOOL hidden;
@property(nonatomic) BOOL suppressed;
@property(nonatomic,copy) NSString *kind;
@end
@implementation LSGCPromptState @end

static BOOL LSGCPromptEnabled(void) {
    NSUserDefaults *d=[NSUserDefaults standardUserDefaults];
    return [d boolForKey:@"hideLockScreenPrompts"];
}
static BOOL LSGCClassInChain(Class c, NSArray *names) {
    for (Class x=c;x;x=class_getSuperclass(x)) if ([names containsObject:NSStringFromClass(x)]) return YES;
    return NO;
}
static BOOL LSGCAncestorLockContext(UIView *v) {
    for (UIView *x=v;x;x=x.superview) {
        NSString *n=NSStringFromClass(x.class);
        if ([n hasPrefix:@"SBUI"]||[n hasPrefix:@"SBUILockScreen"]||[n hasPrefix:@"CSLockScreen"]||[n hasPrefix:@"SBLockScreen"]) return YES;
    }
    return NO;
}
static NSString *LSGCPromptKind(UIView *v, NSString *text) {
    if (!v.window || !LSGCAncestorLockContext(v)) return nil;
    NSString *s=text.lowercaseString;
    // Exact system strings only; never fuzzy-match arbitrary white labels.
    if ([s isEqualToString:@"向上滑动解锁"]||[s isEqualToString:@"向上滑动以解锁"]||[s isEqualToString:@"swipe up to unlock"]||[s isEqualToString:@"swipe up to open"]) {
        if (LSGCClassInChain(v.class,@[@"SBUILockScreenActionButton",@"SBUILockScreenUnlockButton",@"SBUIUnlockLabel",@"SBUILockScreenInstructionLabel"])) return @"unlock";
    }
    if ([s containsString:@"目前电量"]||[s containsString:@"current battery level"]||[s containsString:@"charging"]) {
        if (LSGCClassInChain(v.class,@[@"SBLockScreenBatteryChargingView",@"SBUILockScreenBatteryChargingView",@"SBUIChargingStatusLabel",@"SBLockScreenBatteryTextView"])) return @"charging";
    }
    return nil;
}
static void LSGCRestore(LSGCPromptState *st) {
    UIView *v=st.view; if (!v) return;
    v.alpha=st.alpha; v.hidden=st.hidden; st.suppressed=NO;
}
static void LSGCApplyPrompt(UIView *v, NSString *text) {
    LSGCPromptState *st=objc_getAssociatedObject(v,LSGCPromptStateKey);
    NSString *kind=LSGCPromptKind(v,text);
    if (!st && kind) { st=[LSGCPromptState new]; st.view=v; st.alpha=v.alpha; st.hidden=v.hidden; st.kind=kind; objc_setAssociatedObject(v,LSGCPromptStateKey,st,OBJC_ASSOCIATION_RETAIN_NONATOMIC); if (!LSGCPromptObjects) LSGCPromptObjects=[NSMutableSet set]; [LSGCPromptObjects addObject:st]; }
    if (!st) return;
    if (!LSGCPromptEnabled()||!kind||![st.kind isEqualToString:kind]) { LSGCRestore(st); return; }
    // Hide only the identified text view. Its host and quick-action siblings remain untouched.
    v.alpha=0; v.hidden=YES; st.suppressed=YES;
}
static void LSGCInstallClass(Class cls) {
    if (!cls) return;
    NSArray *allowed=@[@"SBUILockScreenActionButton",@"SBUILockScreenUnlockButton",@"SBUIUnlockLabel",@"SBUILockScreenInstructionLabel",@"SBLockScreenBatteryChargingView",@"SBUILockScreenBatteryChargingView",@"SBUIChargingStatusLabel",@"SBLockScreenBatteryTextView"];
    if (!LSGCClassInChain(cls,allowed)) return;
    for (NSString *name in @[@"setText:",@"setAttributedText:"]) {
        SEL sel=NSSelectorFromString(name); Method m=class_getInstanceMethod(cls,sel); if (!m) continue;
        IMP old=method_getImplementation(m); const char *types=method_getTypeEncoding(m);
        void (^block)(id,id)=^(id obj,id value){ ((void(*)(id,SEL,id))old)(obj,sel,value); NSString *s=[value isKindOfClass:NSAttributedString.class]?[(NSAttributedString *)value string]:([value isKindOfClass:NSString.class]?value:nil); dispatch_async(dispatch_get_main_queue(),^{ LSGCApplyPrompt((UIView *)obj,s); }); };
        class_replaceMethod(cls,sel,imp_implementationWithBlock(block),types);
    }
    SEL moved=@selector(didMoveToWindow); Method mm=class_getInstanceMethod(cls,moved); if (mm) { IMP old=method_getImplementation(mm); void (^block)(id)=^(id obj){ ((void(*)(id,SEL))old)(obj,moved); dispatch_async(dispatch_get_main_queue(),^{ if (!((UIView *)obj).window) { LSGCPromptState *st=objc_getAssociatedObject(obj,LSGCPromptStateKey); if(st) LSGCRestore(st); } }); }; class_replaceMethod(cls,moved,imp_implementationWithBlock(block),method_getTypeEncoding(mm)); }
}
void LSGCHideSystemPromptsInstall(void) {
    if (LSGCPromptInstalled) return; LSGCPromptInstalled=YES; LSGCPromptObjects=[NSMutableSet set];
    NSArray *names=@[@"SBUILockScreenActionButton",@"SBUILockScreenUnlockButton",@"SBUIUnlockLabel",@"SBUILockScreenInstructionLabel",@"SBLockScreenBatteryChargingView",@"SBUILockScreenBatteryChargingView",@"SBUIChargingStatusLabel",@"SBLockScreenBatteryTextView"];
    for (NSString *n in names) LSGCInstallClass(NSClassFromString(n));
}
void LSGCHideSystemPromptsRefresh(void) {
    dispatch_async(dispatch_get_main_queue(),^{ for (LSGCPromptState *st in [LSGCPromptObjects allObjects]) { UIView *v=st.view; if (!v) continue; if (!LSGCPromptEnabled()) LSGCRestore(st); else if (st.kind.length && v.window) { v.alpha=0; v.hidden=YES; st.suppressed=YES; } } });
}
void LSGCHideSystemPromptsClear(void) {
    dispatch_async(dispatch_get_main_queue(),^{ for (LSGCPromptState *st in [LSGCPromptObjects allObjects]) LSGCRestore(st); [LSGCPromptObjects removeAllObjects]; });
}
