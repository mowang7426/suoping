#import "LSGCNotificationOwnerDiscovery.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <cstring>
#include <initializer_list>
namespace {
constexpr NSUInteger Budget=192, ParentBudget=12;
static BOOL ABI(id o,const char *name,char result) {
    if (!o) return NO;
    Method m=class_getInstanceMethod(object_getClass(o),sel_registerName(name));
    if (!m || method_getNumberOfArguments(m)!=2) return NO;
    char *t=method_copyReturnType(m); const char *p=t;
    while (p && *p && strchr("rnNoORV",*p)) ++p;
    BOOL ok=p && *p==result; free(t); return ok;
}
static BOOL Kind(id o,const char *name) { Class c=objc_getClass(name); return c && [o isKindOfClass:c]; }
static id Parent(id o) { id p=nil; LSGCOwnerObjectGetter(o,"parentViewController",&p); return p; }
static BOOL Below(id candidate,id root) {
    if (!root) return NO;
    for (NSUInteger i=0;candidate && i<ParentBudget;++i,candidate=Parent(candidate)) if (candidate==root) return YES;
    return NO;
}
}
BOOL LSGCOwnerObjectGetter(id object,const char *selector,id *value) {
    if (!ABI(object,selector,'@')) return NO;
    if (value) *value=((id(*)(id,SEL))objc_msgSend)(object,sel_registerName(selector));
    return YES;
}
NSString *LSGCOwnerParentChain(id object) {
    NSMutableArray *names=[NSMutableArray array];
    for (NSUInteger i=0;object && i<ParentBudget;++i,object=Parent(object)) [names addObject:NSStringFromClass([object class])];
    return [names componentsJoinedByString:@" > "];
}
BOOL LSGCOwnerVerified(id candidate,id combined,NSString **reason) {
    NSString *why=@"not-cover-sheet-combined"; BOOL ok=NO;
    if (!Kind(candidate,"NCNotificationStructuredListViewController")) why=@"candidate-class-rejected";
    else if (Kind(combined,"CSCombinedListViewController")) {
        id native=nil;
        if (!LSGCOwnerObjectGetter(combined,"notificationListViewController",&native)) why=@"owner-getter-abi-unavailable";
        else if (native==candidate) { ok=YES; why=@"explicit-getter-identity"; }
        else if (native && Below(candidate,native) && Below(native,combined)) { ok=YES; why=@"getter-container-parent-chain"; }
        else why=native?@"owner-getter-identity-mismatch":@"owner-getter-nil";
        // iOS17 header declares this typed ivar. Never assume its existence,
        // offset or type. Runtime checks exact declared type AND object identity.
        if (!ok) {
            Ivar iv=class_getInstanceVariable(object_getClass(combined),"_structuredListViewController");
            const char *type=iv?ivar_getTypeEncoding(iv):nullptr;
            if (type && !strcmp(type,"@\"NCNotificationStructuredListViewController\"") && object_getIvar(combined,iv)==candidate) {
                ok=YES; why=@"explicit-typed-ivar-identity";
            }
        }
    }
    if (reason) *reason=why; return ok;
}
NSArray *LSGCDiscoverNotificationOwners(NSArray *roots,NSDictionary **diagnostic) {
    NSMutableArray *todo=[NSMutableArray array],*lists=[NSMutableArray array],*combined=[NSMutableArray array];
    NSHashTable *seen=[NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    __block BOOL exceeded=NO;
    void (^add)(id)=^(id o) { if (!o || [seen containsObject:o]) return; if (todo.count>=Budget) { exceeded=YES; return; } [seen addObject:o]; [todo addObject:o]; };
    for (id root in roots) add(root);
    NSString *last=@"none",*chain=@"none",*why=@"no-structured-candidate";
    for (NSUInteger i=0;i<todo.count && i<Budget;++i) {
        id o=todo[i];
        if (Kind(o,"CSCombinedListViewController")) {
            [combined addObject:o]; id native=nil; LSGCOwnerObjectGetter(o,"notificationListViewController",&native); add(native);
            Ivar iv=class_getInstanceVariable(object_getClass(o),"_structuredListViewController");
            const char *type=iv?ivar_getTypeEncoding(iv):nullptr;
            if (type && !strcmp(type,"@\"NCNotificationStructuredListViewController\"")) add(object_getIvar(o,iv));
        }
        if (Kind(o,"NCNotificationStructuredListViewController")) { [lists addObject:o]; last=NSStringFromClass([o class]); chain=LSGCOwnerParentChain(o); }
        id children=nil;
        if (LSGCOwnerObjectGetter(o,"childViewControllers",&children) && [children isKindOfClass:NSArray.class]) {
            NSUInteger n=0; for (id child in children) { if (++n>Budget) { exceeded=YES; break; } add(child); }
        }
        for (const char *s:{"presentedViewController","nextResponder","parentViewController"}) { id v=nil; LSGCOwnerObjectGetter(o,s,&v); add(v); }
    }
    NSMutableArray *valid=[NSMutableArray array];
    for (id list in lists) for (id host in combined) if (LSGCOwnerVerified(list,host,&why)) { [valid addObject:list]; break; }
    if (diagnostic) *diagnostic=@{@"nodes":@(todo.count),@"candidates":@(lists.count),@"combined":@(combined.count),@"accepted":@(valid.count),@"budgetExceeded":@(exceeded),@"lastCandidate":last,@"parentChain":chain,@"ownership":why};
    // Exhausted traversal is inconclusive. Never attach a partial arbitrary hit.
    return exceeded?@[]:valid;
}
BOOL LSGCNotificationLockGate(id manager,NSString **diagnostic) {
    NSMutableArray *values=[NSMutableArray array]; BOOL valid=YES; bool flags[4]={false,false,true,true};
    const char *checks[]={"isUILocked","isLockScreenVisible","_isPasscodeVisible","isPasscodeEntryTransientOverlayVisible"};
    for (unsigned i=0;i<4;++i) {
        BOOL cppBool=ABI(manager,checks[i],'B'), objcBool=ABI(manager,checks[i],'c');
        BOOL available=cppBool || objcBool; valid=valid && available;
        // These four declared boolean getters alone permit BOOL's signed-char
        // encoding. Do not treat integers, objects or missing methods as bools.
        if (cppBool) flags[i]=((bool(*)(id,SEL))objc_msgSend)(manager,sel_registerName(checks[i]));
        else if (objcBool) flags[i]=((signed char(*)(id,SEL))objc_msgSend)(manager,sel_registerName(checks[i]))!=0;
        [values addObject:[NSString stringWithFormat:@"%s=%@ abi=%s",checks[i],available?(flags[i]?@"1":@"0"):@"missing-or-ABI",cppBool?"B":(objcBool?"c":"rejected")]];
    }
    BOOL locked=valid && flags[0] && flags[1] && !flags[2] && !flags[3];
    if (diagnostic) *diagnostic=[NSString stringWithFormat:@"%@ gate=%d",[values componentsJoinedByString:@","],locked];
    return locked;
}
