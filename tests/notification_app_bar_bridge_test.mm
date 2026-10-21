#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "../LSGCNotificationsAppBar.h"
#include <cassert>
#include <iostream>
extern unsigned LSGCNotificationProjectionDepth;
static NSUInteger displayInserts=0,displayRemoves=0,bodyReads=0;
@interface NCNotificationRequest : NSObject
@property(nonatomic,copy) NSString *sectionIdentifier;
@property(nonatomic,copy) NSString *notificationIdentifier;
@property(nonatomic,copy) NSString *threadIdentifier;
@property(nonatomic,strong) NSDate *timestamp;
@property(nonatomic) NSUInteger originalSection;
@end
@implementation NCNotificationRequest
- (id)content { ++bodyReads; [NSException raise:@"body-access" format:@"forbidden"]; return nil; }
@end
@interface NCNotificationStructuredSectionList : NSObject
@property(nonatomic,strong) NSMutableArray *items;
@property(nonatomic,readonly) NSArray *allNotificationRequests;
@end
@implementation NCNotificationStructuredSectionList
- (instancetype)init { if ((self=[super init])) _items=[NSMutableArray array]; return self; }
- (NSArray *)allNotificationRequests { return [self.items copy]; }
@end
@interface NCNotificationMasterList : NSObject
@property(nonatomic,copy) NSArray *notificationListSections;
@end
@implementation NCNotificationMasterList @end
@interface NCNotificationStructuredListViewController : NSObject
@property(nonatomic,strong) NCNotificationMasterList *masterList;
@property(nonatomic,copy) void (^onRemove)(id);
@property(nonatomic) BOOL noOpRemove;
@property(nonatomic) BOOL noOpInsert;
@property(nonatomic,strong) NSMutableArray *insertTrace;
@property(nonatomic,strong) NSMutableSet *externalFilteredApps;
@property(nonatomic,strong) NSMutableSet *externallyHidden;
- (void)insertNotificationRequest:(id)request;
- (void)modifyNotificationRequest:(id)request;
- (void)removeNotificationRequest:(id)request;
@end
@implementation NCNotificationStructuredListViewController
- (instancetype)init {
    if ((self=[super init])) {
        _masterList=[NCNotificationMasterList new];
        _masterList.notificationListSections=@[[NCNotificationStructuredSectionList new],[NCNotificationStructuredSectionList new]];
        _insertTrace=[NSMutableArray array]; _externalFilteredApps=[NSMutableSet set]; _externallyHidden=[NSMutableSet set];
    }
    return self;
}
- (void)insertNotificationRequest:(NCNotificationRequest *)request {
    ++displayInserts;
    if (self.noOpInsert) return;
    [self.insertTrace addObject:request.notificationIdentifier];
    NCNotificationStructuredSectionList *section=self.masterList.notificationListSections[request.originalSection];
    NSIndexSet *old=[section.items indexesOfObjectsPassingTest:^BOOL(NCNotificationRequest *r,NSUInteger i,BOOL *stop) {
        (void)i; (void)stop;
        return [r.sectionIdentifier isEqual:request.sectionIdentifier] && [r.notificationIdentifier isEqual:request.notificationIdentifier];
    }];
    [section.items removeObjectsAtIndexes:old]; [section.items addObject:request];
    [section.items sortUsingComparator:^NSComparisonResult(NCNotificationRequest *a,NCNotificationRequest *b) { return [b.timestamp compare:a.timestamp]; }];
    if ([self.externalFilteredApps containsObject:request.sectionIdentifier]) [self.externallyHidden addObject:request];
}
- (void)modifyNotificationRequest:(NCNotificationRequest *)request {
    // Native modify on a projected-away row can be a no-op. Production bridge
    // must update its retained real object instead of forgetting ownership.
    for (NCNotificationStructuredSectionList *s in self.masterList.notificationListSections) {
        for (NCNotificationRequest *r in s.items.copy) if ([r.notificationIdentifier isEqual:request.notificationIdentifier] &&
            [r.sectionIdentifier isEqual:request.sectionIdentifier]) { [self insertNotificationRequest:request]; return; }
    }
}
- (void)removeNotificationRequest:(NCNotificationRequest *)request {
    ++displayRemoves;
    if (self.noOpRemove) return;
    for (NCNotificationStructuredSectionList *s in self.masterList.notificationListSections) {
        NSIndexSet *indices=[s.items indexesOfObjectsPassingTest:^BOOL(NCNotificationRequest *r,NSUInteger i,BOOL *stop) {
            (void)i; (void)stop;
            return [r.notificationIdentifier isEqual:request.notificationIdentifier] && [r.sectionIdentifier isEqual:request.sectionIdentifier];
        }];
        [s.items removeObjectsAtIndexes:indices];
    }
    if (self.onRemove) self.onRemove(request);
}
@end
static NCNotificationRequest *Request(NSString *app,NSString *key,NSUInteger section=0,double timestamp=10) {
    NCNotificationRequest *r=[NCNotificationRequest new]; r.sectionIdentifier=app; r.notificationIdentifier=key;
    r.originalSection=section; r.timestamp=[NSDate dateWithTimeIntervalSince1970:timestamp]; r.threadIdentifier=@"original-native-thread";
    return r;
}
static void Drain(LSGCNotificationProjection *p,BOOL restore=NO) {
    unsigned batches=0; while (restore?[p restore]:[p reconcile]) assert(++batches<1024);
}
static NSUInteger Total(LSGCNotificationProjection *p) { return [[p rows].firstObject[@"count"] unsignedIntegerValue]; }
static BOOL Contains(NCNotificationStructuredListViewController *c,NCNotificationRequest *r) {
    for (NCNotificationStructuredSectionList *s in c.masterList.notificationListSections) if ([s.items containsObject:r]) return YES;
    return NO;
}
int main() { @autoreleasepool {
    NSString *reason=nil;
    assert(!LSGCNotificationsAppBarProviderABI([NSObject new],&reason));
    assert(!LSGCNotificationsAppBarReadSnapshot(nil,&reason).valid);
    NCNotificationStructuredListViewController *c=[NCNotificationStructuredListViewController new];
    assert(LSGCNotificationsAppBarProviderABI(c,&reason));
    auto a=Request(@"a",@"1",0,30),b=Request(@"b",@"1",1,20),b2=Request(@"b",@"2",1,10);
    [c insertNotificationRequest:a]; [c insertNotificationRequest:b]; [c insertNotificationRequest:b2];
    LSGCNotificationProjection *p=[[LSGCNotificationProjection alloc] initWithController:c];
    assert(Total(p)==3 && [p selectApplication:@"a"]);
    Drain(p); assert(p.hiddenCount==2 && Contains(c,a) && !Contains(c,b) && Total(p)==3);
    NSUInteger previous=displayInserts;
    // User/dispatcher withdrawal of a hidden request: original first, then event.
    [c removeNotificationRequest:b]; [p observeRequest:b removed:YES];
    Drain(p,YES); assert(!Contains(c,b) && Contains(c,b2) && p.hiddenCount==0 && displayInserts==previous+1);
    assert(Total(p)==2);
    // Original receive is never intercepted: real row exists before projection.
    auto fresh=Request(@"b",@"3",1,40);
    assert([p selectApplication:@"a"]);
    [c insertNotificationRequest:fresh]; assert(Contains(c,fresh));
    [p observeRequest:fresh removed:NO]; Drain(p); assert(!Contains(c,fresh) && p.hiddenCount==2 && Total(p)==3);
    auto modified=Request(@"b",@"3",1,50);
    [c modifyNotificationRequest:modified]; [p observeRequest:modified removed:NO];
    assert(p.hiddenCount==2);
    [c.insertTrace removeAllObjects]; Drain(p,YES);
    assert(Contains(c,modified) && !Contains(c,fresh) && p.hiddenCount==0);
    assert(([c.insertTrace isEqual:@[@"3",@"2"]]));
    assert([modified.threadIdentifier isEqual:@"original-native-thread"] && modified.originalSection==1);
    // Rapid selection coalesces before applying; last selection wins.
    for (unsigned i=0;i<200;i++) { assert([p selectApplication:i%2?@"a":@"b"]); }
    assert([p selectApplication:@"b"]); Drain(p); assert(p.hiddenCount==1 && !Contains(c,a));
    // Clear the selected application's visible requests; empty selection => All.
    [c removeNotificationRequest:modified]; [p observeRequest:modified removed:YES];
    [c removeNotificationRequest:b2]; [p observeRequest:b2 removed:YES];
    Drain(p); assert(!p.selected.length && Contains(c,a) && p.hiddenCount==0);
    // External filtering must remain native-owned on restoration, not force-shown.
    [c insertNotificationRequest:b2]; [c.externalFilteredApps addObject:@"b"];
    assert([p selectApplication:@"a"]); Drain(p); Drain(p,YES);
    assert([c.externallyHidden containsObject:b2] && p.hiddenCount==0);
    // Reentrant withdrawal while our display remove is executing must tombstone
    // BEFORE remove returns. Reentrant reconcile has a finite pending guard.
    assert([p selectApplication:@"a"]);
    __weak LSGCNotificationProjection *weakProjection=p;
    c.onRemove=^(id r) { [weakProjection observeRequest:r removed:YES]; [weakProjection reconcile]; };
    Drain(p); assert(!p.hiddenCount);
    c.onRemove=nil; previous=displayInserts; Drain(p,YES); assert(displayInserts==previous && !Contains(c,b2));
    // Exact real selector ABI validation, not respondsToSelector-only gating.
    SEL sel=@selector(removeNotificationRequest:);
    Method method=class_getInstanceMethod(c.class,sel); IMP implementation=method_getImplementation(method);
    std::string encoding=method_getTypeEncoding(method);
    class_replaceMethod(c.class,sel,implementation,"B@:@");
    assert(!LSGCNotificationsAppBarProviderABI(c,&reason));
    class_replaceMethod(c.class,sel,implementation,encoding.c_str());
    assert(LSGCNotificationsAppBarProviderABI(c,&reason));
    // Duplicate identities are counted once, even across arrays/sections.
    NCNotificationStructuredSectionList *s=c.masterList.notificationListSections[0];
    [s.items addObject:a]; assert(Total(p)==1); [s.items removeLastObject];
    auto bad=Request(@"",@"bad"); [s.items addObject:bad];
    assert(!LSGCNotificationsAppBarReadSnapshot(c,&reason).valid); [s.items removeLastObject];
    // Batches have a bounded native mutation budget and recover all requests.
    for (unsigned i=0;i<100;i++) [c insertNotificationRequest:Request(@"b",[NSString stringWithFormat:@"%u",i],1,i)];
    assert([p selectApplication:@"a"]); NSUInteger before=displayRemoves;
    BOOL pending=[p reconcile]; assert(pending && displayRemoves-before<=32);
    Drain(p); assert(p.hiddenCount==100 && Total(p)==101);
    Drain(p,YES); assert(p.hiddenCount==0 && Total(p)==101);
    for (unsigned i=0;i<40;i++) { assert([p selectApplication:@"a"]); Drain(p); Drain(p,YES); assert(p.hiddenCount==0); }
    // A no-op native implementation is NOT a successful applied filter.
    NCNotificationStructuredListViewController *noOp=[NCNotificationStructuredListViewController new];
    auto na=Request(@"a",@"na"),nb=Request(@"b",@"nb");
    [noOp insertNotificationRequest:na]; [noOp insertNotificationRequest:nb];
    LSGCNotificationProjection *np=[[LSGCNotificationProjection alloc] initWithController:noOp];
    noOp.noOpRemove=YES; assert([np selectApplication:@"a"]); Drain(np);
    assert(!np.hiddenCount && !np.selected.length && ![np selectApplication:@"a"]);
    assert([np.reason isEqual:@"native-display-remove-not-applied"] && Contains(noOp,nb));
    noOp.noOpRemove=NO;
    np=[[LSGCNotificationProjection alloc] initWithController:noOp];
    assert([np selectApplication:@"a"]); Drain(np); assert(np.hiddenCount==1);
    noOp.noOpInsert=YES; Drain(np,YES);
    assert(np.hiddenCount==1 && [np.reason isEqual:@"native-display-restore-not-applied"]);
    noOp.noOpInsert=NO; Drain(np,YES); assert(!np.hiddenCount && Contains(noOp,nb));
    // A disappeared presentation owner is not retained by its restoration bridge.
    __weak NCNotificationStructuredListViewController *weakController;
    LSGCNotificationProjection *orphan;
    @autoreleasepool {
        NCNotificationStructuredListViewController *d=[NCNotificationStructuredListViewController new]; weakController=d;
        [d insertNotificationRequest:Request(@"a",@"x")]; [d insertNotificationRequest:Request(@"b",@"y")];
        orphan=[[LSGCNotificationProjection alloc] initWithController:d];
        assert([orphan selectApplication:@"a"]); Drain(orphan); assert(orphan.hiddenCount==1);
    }
    assert(!weakController); [orphan sourceDestroyed]; assert(orphan.hiddenCount==0 && !orphan.selected.length);
    previous=displayInserts; Drain(orphan,YES); assert(displayInserts==previous);
    assert(!LSGCNotificationProjectionDepth && !bodyReads && displayInserts>0 && displayRemoves>0);
    std::cout << "PASS production Foundation bridge: active insertion/removal, hidden withdrawal and user clear never resurrect, restore and native order/thread metadata, latest object modification, original-first arrival, external filter ownership, rapid switching, bounded batches/reentrancy, weak source destruction, identity dedup/invalid ABI, no body reads\n";
} }
