#import "LSGCJikanETAAdapter.h"
#import "LSGCJikanRuntimePolicy.h"
#import <CoreFoundation/CoreFoundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#include <string.h>

static NSString *const LSGCSettingsSuite = @"com.minis.lockscreengradientclock";
static LSGCJikanETASnapshot *LSGCJikanSnapshot;
static NSDictionary *LSGCLastDictionary;
static LSGCJikanSession LSGCSession = {1, false, false, 0};
static NSString *LSGCReason = @"not observed", *LSGCLastEvent = @"none";
static NSString *LSGCActualSource = @"unknown", *LSGCStatus = @"unknown";
static id LSGCRawSeconds, LSGCRawTarget;

@implementation LSGCJikanETASnapshot
- (instancetype)initWithSeconds:(NSInteger)s target:(NSInteger)t timestamp:(NSTimeInterval)ts source:(NSString *)src algorithm:(NSString *)alg generation:(uint64_t)g {
    if ((self=[super init])) { _remainingSeconds=s; _targetPercent=t; _timestamp=ts; _source=[src copy]; _algorithm=[alg copy]; _generation=g; }
    return self;
}
@end
BOOL LSGCJikanETAEnabled(void) {
    id v=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("useJikanETA"),(__bridge CFStringRef)LSGCSettingsSuite));
    return [v respondsToSelector:@selector(boolValue)] && [v boolValue];
}
// Legacy source preference is deliberately ignored: the producer already selects
// and validates source/target in publishBatteryDictionary:generation:publisher:.
NSString *LSGCJikanETASource(void) { return @"auto"; }

static void LSGCReject(NSString *why) { LSGCReason=why; LSGCJikanSnapshot=nil; }
static BOOL LSGCNumber(id value, double *out) {
    if (![value isKindOfClass:NSNumber.class]) return NO;
    double x=[value doubleValue]; if (!isfinite(x)) return NO; *out=x; return YES;
}
static BOOL LSGCScalar(id value, double *out) {
    return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value)!=CFBooleanGetTypeID() && LSGCNumber(value,out);
}
static BOOL LSGCBool(NSDictionary *d, NSString *key, BOOL *out) {
    double x; if (!LSGCNumber(d[key], &x) || (x!=0 && x!=1)) return NO;
    *out=x!=0; return YES;
}
// Exact id (*)(id,SEL) ABI, with method signature checked BEFORE invocation.
static id LSGCReadLatest(Class cls) {
    SEL sel=NSSelectorFromString(@"latestSnapshot");
    if (![cls respondsToSelector:sel]) { LSGCReject(@"selector mismatch: latestSnapshot missing"); return nil; }
    NSMethodSignature *sig=[cls methodSignatureForSelector:sel];
    if (!sig || sig.numberOfArguments!=2 || strcmp(sig.methodReturnType,@encode(id)) || strcmp([sig getArgumentTypeAtIndex:0],@encode(id)) || strcmp([sig getArgumentTypeAtIndex:1],@encode(SEL))) {
        LSGCReject(@"selector mismatch: expected object-return no-argument getter"); return nil;
    }
    return ((id(*)(id,SEL))objc_msgSend)((id)cls,sel);
}
static void LSGCRead(BOOL charging, BOOL publication) {
    if (!NSThread.isMainThread) return; // Never synchronously wait for SpringBoard.
    LSGCRawSeconds=nil; LSGCRawTarget=nil; LSGCActualSource=@"unknown"; LSGCStatus=@"unknown";
    LSGCLastEvent=publication ? @"TT100BatteryInfoUpdated" : @"battery/lockscreen/settings/layout (not freshness proof)";
    if (!charging || !LSGCJikanETAEnabled()) { LSGCJikanETAInvalidate(); LSGCReject(charging ? @"switch disabled" : @"not charging/session ended"); return; }
    @try {
        Class cls=NSClassFromString(@"TT100");
        if (!cls) { LSGCJikanETAInvalidate(); LSGCReject(@"class missing: Jikan not injected"); return; }
        LSGCReason=@"reading";
        id raw=LSGCReadLatest(cls);
        if (!raw) { LSGCSession.witnessed=false; if (![LSGCReason hasPrefix:@"selector mismatch"]) LSGCReject(@"no snapshot"); return; }
        if (![raw isKindOfClass:NSDictionary.class]) { LSGCSession.witnessed=false; LSGCReject(@"wrong type: latestSnapshot must return NSDictionary"); return; }
        NSDictionary *d=raw;
        BOOL changed=d!=LSGCLastDictionary;
        LSGCLastDictionary=d; // Strong identity baseline; no reuse of a deallocated address.
        double now=NSProcessInfo.processInfo.systemUptime;
        BOOL fresh=LSGCJikanFresh(&LSGCSession,changed,publication,now);
        LSGCRawSeconds=d[@"remainingSeconds"]; LSGCRawTarget=d[@"targetPercent"];
        LSGCActualSource=[d[@"estimateSource"] isKindOfClass:NSString.class] ? d[@"estimateSource"] : @"unknown";
        LSGCStatus=[d[@"estimateStatus"] isKindOfClass:NSString.class] ? d[@"estimateStatus"] : @"unknown";
        BOOL has=NO,full=NO,reached=NO,external=NO,isCharging=NO;
        if (!LSGCBool(d,@"hasEstimate",&has) || !LSGCBool(d,@"isFullyCharged",&full) || !LSGCBool(d,@"targetReached",&reached) || !LSGCBool(d,@"externalPowerConnected",&external) || !LSGCBool(d,@"isCharging",&isCharging)) { LSGCReject(@"wrong type: estimate/charging flags"); return; }
        if (!has || full || reached || !external || !isCharging || ![LSGCStatus isEqualToString:@"available"]) { LSGCReject(@"no estimate/target reached/full/not charging/status unavailable"); return; }
        if (!([LSGCActualSource isEqualToString:@"jikan"] || [LSGCActualSource isEqualToString:@"apple"])) { LSGCReject(@"source unknown (auto accepts jikan/apple)"); return; }
        double sec=0,target=0,percent=0;
        if (!LSGCScalar(d[@"remainingSeconds"],&sec) || !isfinite(sec) || sec<=0 || sec>86400) { LSGCReject(@"seconds invalid (requires positive seconds <=86400)"); return; }
        if (!LSGCScalar(d[@"targetPercent"],&target) || !LSGCJikanNumbers(sec,target)) { LSGCReject(@"target invalid (requires explicit integer 1..100)"); return; }
        if (!LSGCScalar(d[@"displayPercent"],&percent) || percent<0 || percent>100 || floor(percent)!=percent || percent>=target) { LSGCReject(@"target/displayPercent reached or unknown"); return; }
        if (!fresh) { LSGCReject(@"stale: waiting for changed snapshot at producer publication (max observation age 300s)"); return; }
        LSGCReason=@"available (auto source; producer publication witnessed)";
        LSGCJikanSnapshot=[[LSGCJikanETASnapshot alloc] initWithSeconds:(NSInteger)ceil(sec) target:(NSInteger)target timestamp:now source:LSGCActualSource algorithm:@"TT100.runtime" generation:LSGCSession.generation];
    } @catch (NSException *e) { LSGCSession.witnessed=false; LSGCReject([@"runtime exception: " stringByAppendingString:e.name ?: @"unknown"]); }
}
LSGCJikanETASnapshot *LSGCJikanETACurrentSnapshot(void) {
    if (!NSThread.isMainThread || !LSGCSession.active || !LSGCSession.witnessed || NSProcessInfo.processInfo.systemUptime-LSGCSession.observed>300) return nil;
    return LSGCJikanSnapshot;
}
void LSGCJikanETAInvalidate(void) {
    if (!NSThread.isMainThread) return;
    LSGCJikanSessionEnd(&LSGCSession); LSGCJikanSnapshot=nil;
    // Keep identity baseline across disable/unplug: an old pointer isn't new data.
}
void LSGCJikanETARefresh(BOOL charging) { LSGCRead(charging,NO); }
void LSGCJikanETAProducerPublished(BOOL charging) { LSGCRead(charging,YES); }
NSString *LSGCJikanETAReport(void) {
    return [NSString stringWithFormat:@"JikanETA: reason=%@; sourceMode=auto; source=%@; status=%@; seconds=%@; target=%@; generation=%llu; active=%d; witnessed=%d; observationAge=%.1fs; lastEvent=%@; getter=main-thread/read-only; timestamp=local-monotonic-observation-not-producer-time",LSGCReason,LSGCActualSource,LSGCStatus,LSGCRawSeconds ?: @"unknown",LSGCRawTarget ?: @"unknown",LSGCSession.generation,LSGCSession.active,LSGCSession.witnessed,LSGCSession.witnessed ? NSProcessInfo.processInfo.systemUptime-LSGCSession.observed : -1,LSGCLastEvent];
}
