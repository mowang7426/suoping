#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "../LSGCNotificationOwnerDiscovery.h"
#include "../LSGCNotificationOwnerPolicy.h"
#include <cassert>
#include <iostream>
@interface Node : NSObject
@property(nonatomic,weak) Node *parentViewController;
@property(nonatomic,copy) NSArray *childViewControllers;
@property(nonatomic,strong) Node *presentedViewController;
@property(nonatomic,weak) Node *nextResponder;
@end
@implementation Node @end
@interface NCNotificationStructuredListViewController : Node @end
@implementation NCNotificationStructuredListViewController @end
@interface CSCombinedListViewController : Node {
@public NCNotificationStructuredListViewController *_structuredListViewController;
}
@property(nonatomic,strong) Node *notificationListViewController;
@end
@implementation CSCombinedListViewController @end
@interface BadGetter : Node
- (int)notificationListViewController;
@end
@implementation BadGetter
- (int)notificationListViewController { return 7; }
@end
@interface LockManager : NSObject
@property(nonatomic) bool locked,visible,passcode,overlay;
@end
@implementation LockManager
- (bool)isUILocked { return self.locked; }
- (bool)isLockScreenVisible { return self.visible; }
- (bool)_isPasscodeVisible { return self.passcode; }
- (bool)isPasscodeEntryTransientOverlayVisible { return self.overlay; }
@end
@interface CharLockManager : NSObject @end
@implementation CharLockManager
- (signed char)isUILocked { return 1; }
- (signed char)isLockScreenVisible { return 1; }
- (signed char)_isPasscodeVisible { return 0; }
- (signed char)isPasscodeEntryTransientOverlayVisible { return 0; }
@end
@interface IntegerLockManager : NSObject @end
@implementation IntegerLockManager
- (int)isUILocked { return 1; }
- (int)isLockScreenVisible { return 1; }
- (int)_isPasscodeVisible { return 0; }
- (int)isPasscodeEntryTransientOverlayVisible { return 0; }
@end
static NCNotificationStructuredListViewController *List(Node *parent) {
    auto *list=[NCNotificationStructuredListViewController new]; list.parentViewController=parent; return list;
}
static void Chain(Node *parent,Node *child) { parent.childViewControllers=@[child]; child.parentViewController=parent; }
int main() { @autoreleasepool {
    NSDictionary *diag=nil; NSString *why=nil;
    auto *host=[CSCombinedListViewController new]; auto *list=List(host);
    Chain(host,list); host.notificationListViewController=list;
    // Source already exists before enable: discover immediately from root,
    // without a mock didAppear/layout event or cached candidate.
    NSArray *found=LSGCDiscoverNotificationOwners(@[host],&diag);
    assert(found.count==1 && found[0]==list && [diag[@"accepted"] unsignedIntegerValue]==1);
    assert(LSGCOwnerVerified(list,host,&why) && [why isEqual:@"explicit-getter-identity"]);
    // Candidate layout/appear path starts from the child and climbs to owner.
    assert([LSGCDiscoverNotificationOwners(@[list],&diag) containsObject:list]);
    // True child of getter container is accepted; same-class sibling is not.
    auto *container=[Node new]; Chain(host,container); Chain(container,list); host.notificationListViewController=container;
    assert(LSGCOwnerVerified(list,host,&why) && [why isEqual:@"getter-container-parent-chain"]);
    auto *sibling=List(host); host.childViewControllers=@[container,sibling];
    assert(!LSGCOwnerVerified(sibling,host,&why) && [why isEqual:@"owner-getter-identity-mismatch"]);
    assert(![LSGCDiscoverNotificationOwners(@[sibling],&diag) containsObject:sibling]);
    // Explicit iOS17 typed ivar is independently verified, not arbitrary ancestry.
    host.notificationListViewController=sibling; host->_structuredListViewController=list;
    assert(LSGCOwnerVerified(list,host,&why) && [why isEqual:@"explicit-typed-ivar-identity"]);
    host.notificationListViewController=nil; assert(LSGCOwnerVerified(list,host,&why));
    host->_structuredListViewController=nil; assert(!LSGCOwnerVerified(list,host,&why));
    assert([why isEqual:@"owner-getter-nil"]);
    id value=nil; assert(!LSGCOwnerObjectGetter([BadGetter new],"notificationListViewController",&value));
    assert(!LSGCOwnerObjectGetter([Node new],"absent",&value));
    // Responder/presented edges reach real controller; cycles terminate.
    auto *root=[Node new]; root.nextResponder=root; root.presentedViewController=host;
    host.notificationListViewController=list;
    assert([LSGCDiscoverNotificationOwners(@[root],&diag) containsObject:list]);
    // New lock-screen window/root does not inherit the previous source identity.
    auto *newHost=[CSCombinedListViewController new]; auto *newList=List(newHost);
    Chain(newHost,newList); newHost.notificationListViewController=newList;
    found=LSGCDiscoverNotificationOwners(@[newHost],&diag);
    assert(found.count==1 && found[0]==newList && ![found containsObject:list]);
    // Excess nodes fail closed instead of returning the first arbitrary hit.
    NSMutableArray *many=[NSMutableArray array]; for (unsigned i=0;i<250;++i) [many addObject:[Node new]];
    root.childViewControllers=many;
    assert(!LSGCDiscoverNotificationOwners(@[root],&diag).count);
    assert([diag[@"budgetExceeded"] boolValue] && [diag[@"nodes"] unsignedIntegerValue]<=192);
    auto *manager=[LockManager new]; manager.locked=true; manager.visible=true;
    assert(LSGCNotificationLockGate(manager,&why));
    manager.locked=false; assert(!LSGCNotificationLockGate(manager,&why));
    assert([why containsString:@"isUILocked=0"]);
    manager.locked=true; manager.visible=false; assert(!LSGCNotificationLockGate(manager,&why));
    manager.visible=true; manager.passcode=true; assert(!LSGCNotificationLockGate(manager,&why));
    manager.passcode=false; manager.overlay=true; assert(!LSGCNotificationLockGate(manager,&why));
    manager.overlay=false; assert(LSGCNotificationLockGate(manager,&why));
    assert(LSGCNotificationLockGate([CharLockManager new],&why) && [why containsString:@"abi=c"]);
    assert(!LSGCNotificationLockGate([IntegerLockManager new],&why) && [why containsString:@"missing-or-ABI"]);
    assert(!LSGCNotificationLockGate([NSObject new],&why));
    assert([why containsString:@"isUILocked=missing-or-ABI"] && [why containsString:@"isPasscodeEntryTransientOverlayVisible=missing-or-ABI"]);
    using LSGCNotificationOwner::GapFits;
    assert(GapFits(700,800,300,52));
    assert(!GapFits(780,800,300,52)); // full-screen cards: MUST NOT claim mounted
    assert(!GapFits(700,800,120,52));
    assert(!GapFits(NAN,800,300,52));
    assert(!GapFits(700,800,300,30));
    std::cout << "PASS production owner bridge: pre-existing source discovery, exact/getter-container/typed-ivar ownership, sibling rejection, candidate child/parent/presented/responder paths, root changes, ABI rejection, bounded cycles/budget, lock/unlock/passcode/missing-selector diagnostics, mount-space policy\n";
} return 0; }
