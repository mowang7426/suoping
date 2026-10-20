#import "LSGCJikanETAAdapter.h"
#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>
#import <math.h>

static NSString *const LSGCJikanSuite = @"moe.waru.jikan.estimate-status";
static NSString *const LSGCSettingsSuite = @"com.minis.lockscreengradientclock";
static dispatch_queue_t LSGCJikanQueue;
static LSGCJikanETASnapshot *LSGCJikanSnapshot;
static uint64_t LSGCJikanGeneration = 1;
static BOOL LSGCJikanLastCharging;

@implementation LSGCJikanETASnapshot
- (instancetype)initWithSeconds:(NSInteger)s target:(NSInteger)t timestamp:(NSTimeInterval)ts source:(NSString *)src algorithm:(NSString *)alg generation:(uint64_t)g {
    if ((self=[super init])) { _remainingSeconds=s; _targetPercent=t; _timestamp=ts; _source=[src copy]; _algorithm=[alg copy]; _generation=g; }
    return self;
}
@end

BOOL LSGCJikanETAEnabled(void) {
    id v=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)@"useJikanETA",(__bridge CFStringRef)LSGCSettingsSuite));
    return [v respondsToSelector:@selector(boolValue)] && [v boolValue];
}
NSString *LSGCJikanETASource(void) {
    id v=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)@"jikanETASource",(__bridge CFStringRef)LSGCSettingsSuite));
    return [v isKindOfClass:NSString.class] && [v isEqualToString:@"apple"] ? @"apple" : @"jikan";
}
static BOOL LSGCNumber(id value, double *out) {
    if (![value isKindOfClass:NSNumber.class]) return NO;
    double x=[value doubleValue]; if (!isfinite(x)) return NO; *out=x; return YES;
}
static LSGCJikanETASnapshot *LSGCValidate(NSDictionary *latest, uint64_t generation, NSTimeInterval now, NSString *wanted) {
    if (![latest isKindOfClass:NSDictionary.class]) return nil;
    NSString *status=latest[@"status"]; NSString *source=latest[@"estimateSource"]; NSString *algorithm=latest[@"algorithm"];
    if (![status isKindOfClass:NSString.class] || ![status isEqualToString:@"available"] || ![source isKindOfClass:NSString.class] || ![algorithm isKindOfClass:NSString.class]) return nil;
    if (![source isEqualToString:wanted]) return nil;
    NSString *a=algorithm.lowercaseString;
    if (!( [a containsString:@"jikan"] || [a containsString:@"apple"] || [a containsString:@"tt100"] || [a containsString:@"tt80"] || [a containsString:@"ttl"] )) return nil;
    double ts=0; if (!LSGCNumber(latest[@"timestamp"],&ts) || ts > now+60 || now-ts > 300) return nil;
    id sec=latest[@"remainingSeconds"] ?: latest[@"seconds"]; double seconds=0; if (!LSGCNumber(sec,&seconds) || seconds<=0 || seconds>86400) return nil;
    double target=0; if (!LSGCNumber(latest[@"targetPercent"],&target) || target<1 || target>100 || floor(target)!=target) return nil;
    return [[LSGCJikanETASnapshot alloc] initWithSeconds:(NSInteger)seconds target:(NSInteger)target timestamp:ts source:source algorithm:algorithm generation:generation];
}
static void LSGCJikanEnsureQueue(void) { static dispatch_once_t once; dispatch_once(&once,^{ LSGCJikanQueue=dispatch_queue_create("com.minis.lockscreengradientclock.jikan-read",DISPATCH_QUEUE_SERIAL); }); }
LSGCJikanETASnapshot *LSGCJikanETACurrentSnapshot(void) { return LSGCJikanSnapshot; }
void LSGCJikanETAInvalidate(void) { LSGCJikanGeneration++; LSGCJikanSnapshot=nil; }
void LSGCJikanETARefresh(BOOL charging) {
    LSGCJikanLastCharging=charging;
    if (!charging) { LSGCJikanETAInvalidate(); return; }
    LSGCJikanEnsureQueue(); uint64_t g=LSGCJikanGeneration;
    dispatch_async(LSGCJikanQueue, ^{
        // All preference reads, including opt-in/source, stay off SpringBoard main.
        if (!LSGCJikanETAEnabled()) return;
        NSString *wanted=[LSGCJikanETASource() copy];
        CFPropertyListRef raw=CFPreferencesCopyValue(CFSTR("latest"),(__bridge CFStringRef)LSGCJikanSuite,kCFPreferencesCurrentUser,kCFPreferencesAnyHost);
        NSDictionary *latest=CFBridgingRelease(raw); LSGCJikanETASnapshot *s=LSGCValidate(latest,g,[NSDate date].timeIntervalSince1970,wanted);
        dispatch_async(dispatch_get_main_queue(),^{ if (g==LSGCJikanGeneration && LSGCJikanLastCharging) LSGCJikanSnapshot=s; });
    });
}
