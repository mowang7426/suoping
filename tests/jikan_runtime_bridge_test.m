#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import "../LSGCJikanETAAdapter.h"
#include <assert.h>
static id raw;
static NSUInteger reads, recomputes;
static id getLatest(__unused id self,__unused SEL cmd) { assert(NSThread.isMainThread); reads++; return raw; }
static double wrongABI(__unused id self,__unused SEL cmd) { return 3; }
static id throwing(__unused id self,__unused SEL cmd) { @throw [NSException exceptionWithName:@"MockException" reason:nil userInfo:nil]; }
static NSDictionary *good(void) { return [@{@"remainingSeconds":@840,@"targetPercent":@95,@"hasEstimate":@YES,@"targetReached":@NO,@"isFullyCharged":@NO,@"externalPowerConnected":@YES,@"isCharging":@YES,@"displayPercent":@59,@"estimateSource":@"apple",@"estimateStatus":@"available"} mutableCopy]; }
static void setEnabled(BOOL enabled) { CFPreferencesSetAppValue(CFSTR("useJikanETA"),enabled ? kCFBooleanTrue : kCFBooleanFalse,CFSTR("com.minis.lockscreengradientclock")); }
int main(void) { @autoreleasepool {
    setEnabled(YES);
    LSGCJikanETARefresh(YES); assert([LSGCJikanETAReport() containsString:@"class missing"]);
    Class c=objc_allocateClassPair(NSObject.class,"TT100",0); assert(c);
    Class meta=object_getClass(c); SEL sel=NSSelectorFromString(@"latestSnapshot");
    objc_registerClassPair(c);
    LSGCJikanETARefresh(YES); assert([LSGCJikanETAReport() containsString:@"selector mismatch"]);
    class_addMethod(meta,sel,(IMP)getLatest,"@@:");
    raw=nil; LSGCJikanETARefresh(YES); assert(!LSGCJikanETACurrentSnapshot());
    raw=@[@1]; LSGCJikanETARefresh(YES); assert([LSGCJikanETAReport() containsString:@"wrong type"]);
    NSUInteger offMainReads=reads;
    dispatch_sync(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{ LSGCJikanETARefresh(YES); });
    assert(reads==offMainReads);
    raw=good(); LSGCJikanETARefresh(YES); assert(!LSGCJikanETACurrentSnapshot()); // baseline is not publication
    LSGCJikanETAProducerPublished(YES); assert(!LSGCJikanETACurrentSnapshot()); // unchanged old object
    raw=good(); LSGCJikanETAProducerPublished(YES);
    LSGCJikanETASnapshot *s=LSGCJikanETACurrentSnapshot(); assert(s && s.remainingSeconds==840 && s.targetPercent==95); assert([s.source isEqual:@"apple"]); assert([LSGCJikanETASource() isEqual:@"auto"]);
    LSGCJikanETARefresh(YES); assert(LSGCJikanETACurrentSnapshot()); // layouts don't invalidate genuinely fresh data
    uint64_t generation=s.generation;
    LSGCJikanETARefresh(NO); assert(!LSGCJikanETACurrentSnapshot());
    LSGCJikanETAProducerPublished(NO); assert(!LSGCJikanETACurrentSnapshot()); // late unplug result
    LSGCJikanETARefresh(YES); assert(!LSGCJikanETACurrentSnapshot());
    LSGCJikanETAProducerPublished(YES); assert(!LSGCJikanETACurrentSnapshot());
    raw=good(); LSGCJikanETAProducerPublished(YES); assert(LSGCJikanETACurrentSnapshot().generation>generation);
    NSArray *keys=@[@"remainingSeconds",@"targetPercent",@"estimateStatus",@"estimateSource",@"hasEstimate",@"isCharging",@"displayPercent"];
    NSArray *values=@[@0,@94.5,@"unknown",@"unknown",@NO,@NO,@96];
    for (NSUInteger i=0;i<keys.count;i++) { NSMutableDictionary *d=[good() mutableCopy]; d[keys[i]]=values[i]; raw=d; LSGCJikanETAProducerPublished(YES); assert(!LSGCJikanETACurrentSnapshot()); }
    for (NSString *key in @[@"remainingSeconds",@"targetPercent",@"hasEstimate",@"displayPercent"]) { NSMutableDictionary *d=[good() mutableCopy]; [d removeObjectForKey:key]; raw=d; LSGCJikanETAProducerPublished(YES); assert(!LSGCJikanETACurrentSnapshot()); }
    for (id value in @[@YES,@"840",@(-1),@(NAN),@(86401)]) { NSMutableDictionary *d=[good() mutableCopy]; d[@"remainingSeconds"]=value; raw=d; LSGCJikanETAProducerPublished(YES); assert(!LSGCJikanETACurrentSnapshot()); }
    raw=good(); setEnabled(NO); LSGCJikanETAProducerPublished(YES); assert(!LSGCJikanETACurrentSnapshot());
    setEnabled(YES); LSGCJikanETARefresh(YES); assert(!LSGCJikanETACurrentSnapshot());
    class_replaceMethod(meta,sel,(IMP)throwing,"@@:"); LSGCJikanETARefresh(YES); assert([LSGCJikanETAReport() containsString:@"runtime exception"]);
    objc_disposeClassPair(c);
    c=objc_allocateClassPair(NSObject.class,"TT100",0); assert(c);
    class_addMethod(object_getClass(c),sel,(IMP)wrongABI,"d@:"); objc_registerClassPair(c);
    NSUInteger before=reads; LSGCJikanETARefresh(YES); assert(reads==before); assert([LSGCJikanETAReport() containsString:@"selector mismatch"]);
    assert(recomputes==0); // Mock exposes no refresh/start/model/IPC methods: production must not call any.
    CFPreferencesSetAppValue(CFSTR("useJikanETA"),NULL,CFSTR("com.minis.lockscreengradientclock"));
    NSLog(@"PASS production ObjC bridge: actual runtime ABI, main getter, fields, auto source, sessions, missing/invalid/exception, no computation (%lu reads)",(unsigned long)reads);
} return 0; }
