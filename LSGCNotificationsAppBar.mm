#import "LSGCNotificationsAppBar.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <cstring>

// Main-thread synchronous native display transaction guard; not a delivery gate.
unsigned LSGCNotificationProjectionDepth=0;

namespace {
bool ABI(id target,const char *name,char result,const char *args) {
    if (!target) return false;
    Method m=class_getInstanceMethod(object_getClass(target),sel_registerName(name));
    if (!m || method_getNumberOfArguments(m)!=strlen(args)+2) return false;
    auto match=[](const char *s,char c) { while (s && *s && strchr("rnNoORV",*s)) ++s; return s && *s==c; };
    char *t=method_copyReturnType(m); bool ok=match(t,result); free(t);
    for (unsigned i=0;ok && i<strlen(args);++i) { t=method_copyArgumentType(m,i+2); ok=match(t,args[i]); free(t); }
    return ok;
}
bool Native(id o,const char *name) { Class c=objc_getClass(name); return c && [o isKindOfClass:c]; }
id Read(id o,const char *s) { return ((id(*)(id,SEL))objc_msgSend)(o,sel_registerName(s)); }
void Send(id o,const char *s,id r) { ((void(*)(id,SEL,id))objc_msgSend)(o,sel_registerName(s),r); }
NSArray *Key(id request) {
    if (!Native(request,"NCNotificationRequest") || !ABI(request,"sectionIdentifier",'@',"") ||
        !ABI(request,"notificationIdentifier",'@',"")) return nil;
    id a=Read(request,"sectionIdentifier"),k=Read(request,"notificationIdentifier");
    if (![a isKindOfClass:NSString.class] || ![k isKindOfClass:NSString.class] ||
        ![a length] || ![k length] || [a length]>512 || [k length]>512) return nil;
    return @[[a copy],[k copy]];
}
// Copy only the collection, never copy or serialize an NCNotificationRequest.
// Metadata is original enumeration position; native reinsertion uses the unchanged
// request timestamp/thread/options (one-argument iOS17 ABI, no invented coalescing arg).
NSDictionary *Visible(id controller) {
    if (!LSGCNotificationsAppBarProviderABI(controller,nullptr)) return nil;
    id sections=Read(Read(controller,"masterList"),"notificationListSections");
    if (![sections isKindOfClass:NSArray.class] || [sections count]>128) return nil;
    NSMutableDictionary *out=[NSMutableDictionary dictionary]; NSUInteger si=0,total=0;
    for (id section in [sections copy]) {
        if (!Native(section,"NCNotificationStructuredSectionList") || !ABI(section,"allNotificationRequests",'@',"")) return nil;
        id requests=Read(section,"allNotificationRequests");
        if (![requests isKindOfClass:NSArray.class]) return nil;
        NSUInteger ri=0;
        for (id request in [requests copy]) {
            if (++total>8192) return nil;
            NSArray *key=Key(request); if (!key) return nil;
            if (!out[key]) out[key]=@{@"request":request,@"section":@(si),@"position":@(ri)};
            ++ri;
        }
        ++si;
    }
    return out;
}
}
BOOL LSGCNotificationsAppBarProviderABI(id controller,NSString **reason) {
    const char *why="ready";
    if (!NSThread.isMainThread) why="not-main-thread";
    else if (!Native(controller,"NCNotificationStructuredListViewController")) why="unexpected-structured-controller";
    else if (!ABI(controller,"masterList",'@',"") || !ABI(controller,"insertNotificationRequest:",'v',"@") ||
             !ABI(controller,"modifyNotificationRequest:",'v',"@") || !ABI(controller,"removeNotificationRequest:",'v',"@")) why="structured-controller-abi-mismatch";
    else { @try {
        id master=Read(controller,"masterList");
        if (!Native(master,"NCNotificationMasterList") || !ABI(master,"notificationListSections",'@',"")) why="master-list-abi-mismatch";
    } @catch (__unused NSException *e) { why="native-read-exception"; } }
    if (reason) *reason=[NSString stringWithUTF8String:why];
    return strcmp(why,"ready")==0;
}
LSGCNotifications::Snapshot LSGCNotificationsAppBarReadSnapshot(id controller,NSString **reason) {
    LSGCNotifications::Snapshot out;
    @try {
        NSDictionary *visible=Visible(controller);
        if (visible) {
            std::vector<LSGCNotifications::Identity> ids;
            for (NSArray *key in visible) ids.push_back({[key[0] UTF8String],[key[1] UTF8String]});
            out=LSGCNotifications::BuildSnapshot(ids);
        }
    } @catch (__unused NSException *e) { out.reason="native-read-exception"; }
    if (reason) *reason=[NSString stringWithUTF8String:out.reason.c_str()];
    return out;
}

@interface LSGCNotificationProjection ()
@property(nonatomic,strong) NSMutableDictionary<NSArray *,NSDictionary *> *owned;
@property(nonatomic,copy,readwrite) NSString *selected;
@property(nonatomic,copy,readwrite) NSString *reason;
@property(nonatomic) BOOL applying;
@property(nonatomic) BOOL retry;
@property(nonatomic) BOOL failed;
@end
@implementation LSGCNotificationProjection
- (instancetype)initWithController:(id)controller {
    if ((self=[super init])) { _controller=controller; _owned=[NSMutableDictionary dictionary]; _selected=@""; _reason=@"ready"; }
    return self;
}
- (NSUInteger)hiddenCount { return self.owned.count; }
- (NSDictionary *)snapshot {
    @try { return Visible(self.controller); }
    @catch (__unused NSException *e) { self.reason=@"native-read-exception"; return nil; }
}
- (NSArray<NSDictionary *> *)rows {
    NSAssert(NSThread.isMainThread,@"main queue required");
    NSDictionary *visible=[self snapshot]; if (!visible) return @[];
    NSMutableSet *keys=[NSMutableSet setWithArray:visible.allKeys]; [keys addObjectsFromArray:self.owned.allKeys];
    std::vector<LSGCNotifications::Identity> ids;
    for (NSArray *key in keys) ids.push_back({[key[0] UTF8String],[key[1] UTF8String]});
    auto counts=LSGCNotifications::BuildSnapshot(ids);
    if (!counts.valid) { self.reason=@"snapshot-budget-exceeded"; return @[]; }
    NSMutableArray *rows=[NSMutableArray arrayWithObject:@{@"identifier":@"",@"name":@"全部",@"count":@(counts.total)}];
    for (const auto &group:counts.groups) {
        NSString *app=[NSString stringWithUTF8String:group.app.c_str()];
        [rows addObject:@{@"identifier":app,@"name":app,@"count":@(group.count)}];
    }
    return rows;
}
- (void)observeRequest:(id)request removed:(BOOL)removed {
    NSAssert(NSThread.isMainThread,@"main queue required");
    @try {
        NSArray *key=Key(request); if (!key) { self.selected=@""; self.reason=@"invalid-source-identity"; return; }
        // This is called only AFTER the real source/display original. A real
        // removal tombstones our ownership immediately, including reentrancy.
        // New/modified requests are now native-owned, not ours to resurrect.
        if (removed) [self.owned removeObjectForKey:key];
        else if (self.owned[key]) {
            NSDictionary *visible=[self snapshot];
            if (visible[key]) [self.owned removeObjectForKey:key];
            else {
                NSMutableDictionary *entry=[self.owned[key] mutableCopy];
                entry[@"request"]=request; self.owned[key]=entry;
            }
        }
        if (removed) self.reason=@"source-removal-observed";
        if (self.applying) self.retry=YES;
    } @catch (__unused NSException *e) { self.selected=@""; self.reason=@"source-read-exception"; }
}
- (void)observeSectionRemoved:(NSString *)identifier {
    NSAssert(NSThread.isMainThread,@"main queue required");
    if (![identifier isKindOfClass:NSString.class] || !identifier.length || identifier.length>512) return;
    for (NSArray *key in self.owned.allKeys) if ([key[0] isEqual:identifier]) [self.owned removeObjectForKey:key];
    if (self.applying) self.retry=YES;
}
- (BOOL)selectApplication:(NSString *)app {
    NSAssert(NSThread.isMainThread,@"main queue required");
    if (![app isKindOfClass:NSString.class] || app.length>512 || (app.length && self.failed)) return NO;
    BOOL found=!app.length;
    for (NSDictionary *row in [self rows]) if ([row[@"identifier"] isEqual:app]) found=YES;
    if (!found) return NO;
    self.selected=[app copy]; return YES;
}
- (BOOL)reconcile {
    NSAssert(NSThread.isMainThread,@"main queue required");
    if (self.applying) { self.retry=YES; return NO; }
    id controller=self.controller;
    if (!controller) { [self sourceDestroyed]; return NO; }
    NSDictionary *visible=[self snapshot];
    if (!visible) { self.selected=@""; self.reason=@"snapshot-unavailable-restore-pending"; return NO; }
    // Native insertions may have reintroduced a formerly projected request.
    for (NSArray *key in visible) [self.owned removeObjectForKey:key];
    BOOL selectedExists=!self.selected.length;
    for (NSArray *key in visible) if ([key[0] isEqual:self.selected]) selectedExists=YES;
    for (NSArray *key in self.owned) if ([key[0] isEqual:self.selected]) selectedExists=YES;
    if (!selectedExists) self.selected=@"";
    if (!LSGCNotifications::ProjectionWithinBudget(visible.count,self.owned.count)) { self.selected=@""; self.reason=@"projection-budget-restore"; }
    self.applying=YES; self.retry=NO;
    NSUInteger budget=LSGCNotifications::MutationBudget; BOOL more=NO;
    @try {
        // Restore only our own removals, in saved section/enumeration order.
        NSArray *restoreKeys=[self.owned.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSArray *a,NSArray *b) {
            NSDictionary *x=self.owned[a],*y=self.owned[b];
            NSComparisonResult result=[x[@"section"] compare:y[@"section"]];
            if (result==NSOrderedSame) result=[x[@"position"] compare:y[@"position"]];
            return result==NSOrderedSame ? [a[1] compare:b[1]]:result;
        }];
        for (NSArray *key in restoreKeys) {
            if (self.selected.length && ![key[0] isEqual:self.selected]) continue;
            if (!budget) { more=YES; break; } --budget;
            NSDictionary *entry=self.owned[key]; if (!entry) continue;
            LSGCNotificationProjectionDepth++;
            @try { Send(controller,"insertNotificationRequest:",entry[@"request"]); }
            @finally { --LSGCNotificationProjectionDepth; }
            // Native insert owns routing (Focus, digest, grouping, sort). Never
            // overwrite its master array, date, options, filter or migration state.
            // Verify actual transfer back to native ownership. A void selector
            // returning normally is not evidence that restoration succeeded.
            NSDictionary *after=[self snapshot];
            if (self.owned[key] && (!after || !after[key])) {
                self.failed=YES; self.selected=@""; self.reason=@"native-display-restore-not-applied";
                return NO; // keep the real request for explicit recovery, never fake success
            }
            [self.owned removeObjectForKey:key];
        }
        if (!more && self.selected.length) {
            // Snapshot again: original insertion can synchronously change groups.
            visible=[self snapshot];
            if (!visible) { self.selected=@""; more=self.owned.count>0; }
            else for (NSArray *key in visible) {
                if ([key[0] isEqual:self.selected] || self.owned[key]) continue;
                if (!budget) { more=YES; break; } --budget;
                NSDictionary *entry=visible[key];
                // Ownership must precede remove: a nested real withdrawal can
                // erase it and MUST NOT be undone when display remove returns.
                self.owned[key]=entry;
                LSGCNotificationProjectionDepth++;
                @try { Send(controller,"removeNotificationRequest:",entry[@"request"]); }
                @finally { --LSGCNotificationProjectionDepth; }
            }
        }
        NSDictionary *committed=[self snapshot];
        if (!committed) { self.failed=YES; self.selected=@""; self.reason=@"commit-snapshot-unavailable"; return NO; }
        BOOL noOp=NO;
        for (NSArray *key in committed) if (self.owned[key]) { [self.owned removeObjectForKey:key]; noOp=YES; }
        if (noOp) {
            self.failed=YES; self.selected=@""; self.reason=@"native-display-remove-not-applied";
            return self.owned.count>0;
        }
        self.reason=more?@"projection-batch-pending":@"ready";
    } @catch (__unused NSException *e) {
        self.failed=YES; self.selected=@""; self.reason=@"native-projection-exception-restore-pending";
        // Do not discard an owned real request on failure. Caller may restore.
        more=NO;
    } @finally { self.applying=NO; }
    return more || self.retry;
}
- (BOOL)restore {
    self.selected=@"";
    return [self reconcile];
}
- (void)sourceDestroyed {
    // A destroyed presentation owner cannot be reinserted into. System delivery
    // repository was never changed and will populate its next native owner.
    self.controller=nil; [self.owned removeAllObjects]; self.selected=@""; self.reason=@"source-destroyed";
}
@end
