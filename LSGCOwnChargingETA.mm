#import "LSGCOwnChargingETA.h"
#import "LSGCChargingETAPill.h"
#import "LSGCOwnChargingETACore.h"
#import <UIKit/UIKit.h>
#import <mach/mach_time.h>
#import <mach/mach.h>
// Public C IOKit functions; no private Objective-C classes, runtime or model.
extern "C" {
CFMutableDictionaryRef IOServiceMatching(const char *name);
unsigned int IOServiceGetMatchingService(mach_port_t port, CFDictionaryRef matching);
kern_return_t IORegistryEntryCreateCFProperties(unsigned int entry, CFMutableDictionaryRef *properties, CFAllocatorRef allocator, unsigned int options);
kern_return_t IOObjectRelease(unsigned int object);
CFRunLoopSourceRef IOPSNotificationCreateRunLoopSource(void (*callback)(void *), void *context);
}
static dispatch_queue_t Work;
static dispatch_source_t Timer;
static OwnETA::Engine Engine;
static BOOL Loaded, Enabled, Busy, Pending, RequestQueued;
static uint64_t Generation;
static NSInteger LastState=-99, LastPercent=-99;
static NSString *Text;
static double TextStamp;
static NSString *Diagnostic=@"OwnChargingETA(source=none,reason=disabled)";
static CFRunLoopSourceRef PowerEvents;
static void Request(void);
static void ReconcileTimer(BOOL on);
static double Monotonic(void) {
    static mach_timebase_info_data_t scale;
    if (!scale.denom) mach_timebase_info(&scale);
    return (double)mach_continuous_time()*scale.numer/scale.denom/1e9;
}
static NSString *CachePath(void) {
    // Our own small learning-only file, never Jikan preferences or database.
    NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/com.minis.lockscreengradientclock"];
    return [dir stringByAppendingPathComponent:@"own-charge-history-v1.plist"];
}
static double Number(id value) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID()) return NAN;
    double d=[value doubleValue]; return std::isfinite(d)?d:NAN;
}
static BOOL Flag(id v, BOOL fallback) {
    double n=[v isKindOfClass:NSNumber.class]?[v doubleValue]:NAN;
    return (n==0 || n==1)?(BOOL)n:fallback;
}
static void Load(void) {
    if (Loaded) return; Loaded=YES;
    NSString *path=CachePath();
    NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    if ([attrs fileSize]>256*1024) return;
    NSData *data=[NSData dataWithContentsOfFile:path];
    id plist=data?[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:nil]:nil;
    if (![plist isKindOfClass:NSDictionary.class] || ![plist[@"schema"] isEqual:@1]) return;
    double serial=Number(plist[@"serial"]);
    if (!std::isfinite(serial) || serial<0 || serial>1e12) return;
    Engine.serial=(uint64_t)serial;
    double maximum=Number(plist[@"maximum"]);
    if (std::isfinite(maximum) && maximum>=500 && maximum<=15000) Engine.batteryMaximum=maximum;
    id classes=plist[@"classes"];
    if (![classes isKindOfClass:NSDictionary.class] || [classes count]>4) return;
    for (id key in classes) {
        if (![key isKindOfClass:NSString.class] || [key length]>120) continue;
        id buckets=classes[key]; if (![buckets isKindOfClass:NSArray.class] || [buckets count]!=100) continue;
        OwnETA::History h;
        for (int p=0;p<100;p++) {
            id values=buckets[p]; if (![values isKindOfClass:NSArray.class] || [values count]>8) continue;
            for (id item in values) {
                if (![item isKindOfClass:NSArray.class] || [item count]!=3) continue;
                double seconds=Number(item[0]), session=Number(item[1]), wall=Number(item[2]);
                if (seconds>=10 && seconds<=3600 && session>=1 && session<=serial && wall>0 && std::isfinite(wall))
                    h[p].push_back({seconds,(uint64_t)session,wall});
            }
        }
        Engine.histories[[key UTF8String]]=h;
    }
}
static void Save(void) {
    if (!Engine.dirty) return;
    Engine.dirty=false;
    NSMutableDictionary *classes=[NSMutableDictionary dictionary];
    for (const auto &entry:Engine.histories) {
        NSMutableArray *buckets=[NSMutableArray arrayWithCapacity:100];
        for (const auto &bucket:entry.second) {
            NSMutableArray *values=[NSMutableArray array];
            for (const auto &t:bucket) [values addObject:@[@(t.seconds),@(t.session),@(t.wall)]];
            [buckets addObject:values];
        }
        classes[@(entry.first.c_str())]=buckets;
    }
    NSDictionary *plist=@{@"schema":@1,@"serial":@(Engine.serial),@"maximum":@(std::isfinite(Engine.batteryMaximum)?Engine.batteryMaximum:0),@"classes":classes};
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    NSString *path=CachePath();
    [NSFileManager.defaultManager createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    if (data.length<=256*1024 && [data writeToFile:path options:NSDataWritingAtomic error:nil])
        [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:nil];
}
static NSDictionary *ReadPower(kern_return_t *status) {
    unsigned int service=IOServiceGetMatchingService(0,IOServiceMatching("IOPMPowerSource"));
    if (!service) { *status=KERN_FAILURE; return @{}; }
    CFMutableDictionaryRef properties=NULL;
    *status=IORegistryEntryCreateCFProperties(service,&properties,kCFAllocatorDefault,0);
    IOObjectRelease(service);
    id p=CFBridgingRelease(properties);
    return *status==KERN_SUCCESS && [p isKindOfClass:NSDictionary.class]?p:@{};
}
static std::string Charger(NSDictionary *p) {
    id a=p[@"AdapterDetails"];
    if (![a isKindOfClass:NSDictionary.class]) return "unknown";
    // Only non-identifying negotiation data; never serial numbers, names or IDs.
    double watts=Number(a[@"Watts"]), volts=Number(a[@"Voltage"]), amps=Number(a[@"Current"]);
    if (!(watts>0 && watts<=300)) watts=0;
    if (!(volts>0 && volts<=30000)) volts=0;
    if (!(amps>0 && amps<=10000)) amps=0;
    if (!watts && !volts && !amps) return "unknown";
    return [[NSString stringWithFormat:@"w%.0f-v%.0f-i%.0f-wireless%d",watts,volts,amps,Flag(p[@"IsWireless"],NO)] UTF8String];
}
static NSString *Summary(NSDictionary *p, const OwnETA::Input &x, const OwnETA::Result &r, uint64_t generation, kern_return_t kr) {
    NSMutableArray *fields=[NSMutableArray array];
    for (NSString *key in @[@"IsCharging",@"ExternalConnected",@"AppleRawMaxCapacity",@"AppleRawCurrentCapacity",@"InstantAmperage",@"Amperage"]) {
        id v=p[key];
        // Numeric raw values only. No complete registry dump/device identifiers.
        [fields addObject:[NSString stringWithFormat:@"%@=%@",key,[v isKindOfClass:NSNumber.class]?v:@"absent/invalid"]];
    }
    return [NSString stringWithFormat:@"OwnChargingETA(source=%s,reason=%s,IOKit=%d,fields={%@},sanitized={soc=%.1f,max_mAh=%.2f,current_mAh=%.2f,net_mA=%.2f,capacityTrusted=%d,currentPositive=%d},generation=%llu,historyCoverage=%d/%d,samples=%d,etaSeconds=%.1f,coarse=%d; target100 not guaranteed; no device IDs)",r.source.c_str(),r.reason.c_str(),kr,[fields componentsJoinedByString:@","],x.soc,x.maximum,x.capacity,x.current,OwnETA::validCapacity(x),OwnETA::validCurrent(x.current),(unsigned long long)generation,r.coverage,r.needed,r.samples,r.seconds,r.coarse];
}
static void Run(void) {
    RequestQueued=NO;
    if (!Enabled) return;
    UIDevice *d=UIDevice.currentDevice;
    NSInteger state=d.batteryState, percent=LSGCBatteryPercent(d.batteryLevel);
    BOOL connected=(state==UIDeviceBatteryStateCharging || state==UIDeviceBatteryStateFull);
    if (!connected) { LSGCOwnETAObserve(); return; }
    if (Busy) { Pending=YES; return; }
    Busy=YES; Pending=NO;
    uint64_t generation=Generation;
    dispatch_async(Work, ^{
        @autoreleasepool {
            Load(); kern_return_t kr=KERN_FAILURE; NSDictionary *p=ReadPower(&kr);
            OwnETA::Input x;
            x.now=Monotonic(); x.wall=NSDate.date.timeIntervalSince1970; x.soc=percent;
            x.connected=Flag(p[@"ExternalConnected"],connected);
            x.charging=Flag(p[@"IsCharging"],state==UIDeviceBatteryStateCharging);
            x.full=(state==UIDeviceBatteryStateFull || Flag(p[@"FullyCharged"],NO));
            x.maximum=Number(p[@"AppleRawMaxCapacity"]); x.capacity=Number(p[@"AppleRawCurrentCapacity"]);
            x.current=Number(p[@"InstantAmperage"]);
            // A present negative/overflow instant value is NOT replaced with a more flattering field.
            if (!p[@"InstantAmperage"]) x.current=Number(p[@"Amperage"]);
            x.charger=Charger(p);
            OwnETA::Result r=Engine.consume(x); Save();
            NSString *summary=Summary(p,x,r,generation,kr);
            NSString *text=x.connected?nil:@"";
            if (x.connected && percent>=0) {
                if (r.reason=="full") text=@"已充满 · 100%";
                else if (r.reason=="paused_or_net_discharge") text=[NSString stringWithFormat:@"充电暂停 · %ld%%",(long)percent];
                else if (std::isfinite(r.seconds)) text=[NSString stringWithFormat:r.coarse?@"粗估约%ld分钟充满 · %ld%%":@"约%ld分钟充满 · %ld%%",(long)MAX(1,ceil(r.seconds/60)),(long)percent];
                else text=[NSString stringWithFormat:@"正在学习 · %ld%%",(long)percent];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                Busy=NO;
                UIDeviceBatteryState current=UIDevice.currentDevice.batteryState;
                BOOL stillConnected=(current==UIDeviceBatteryStateCharging || current==UIDeviceBatteryStateFull);
                if (OwnETA::acceptGeneration(generation,Generation,Enabled,stillConnected)) {
                    Text=[text copy]; TextStamp=x.now; Diagnostic=[summary copy]; LSGCChargingETAPillRefresh();
                }
                if (Pending && Enabled) Request();
            });
        }
    });
}
static void Request(void) {
    // Called on main, one queued request + one in-flight IOKit task maximum.
    if (!Enabled || RequestQueued) return;
    RequestQueued=YES; dispatch_async(dispatch_get_main_queue(), ^{ Run(); });
}
static void ReconcileTimer(BOOL on) {
    dispatch_async(Work, ^{
        if (!on) { if (Timer) { dispatch_source_cancel(Timer); Timer=nil; } return; }
        if (Timer) return;
        Timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,Work);
        dispatch_source_set_timer(Timer,dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC),30*NSEC_PER_SEC,5*NSEC_PER_SEC);
        dispatch_source_set_event_handler(Timer, ^{ dispatch_async(dispatch_get_main_queue(), ^{ Request(); }); });
        dispatch_resume(Timer);
    });
}
static void PowerChanged(void *context) {
    (void)context;
    // IOPS source is on main runloop; no registry access here.
    LSGCOwnETAObserve(); Request();
}
void LSGCOwnETAObserve(void) {
    NSCAssert(NSThread.isMainThread,@"main-only UIDevice capture");
    if (!Enabled) return;
    UIDevice *d=UIDevice.currentDevice;
    NSInteger state=d.batteryState, percent=LSGCBatteryPercent(d.batteryLevel);
    if (state==LastState && percent==LastPercent) return;
    BOOL stateChanged=(state!=LastState);
    LastState=state; LastPercent=percent; ++Generation; Text=nil;
    BOOL connected=(state==UIDeviceBatteryStateCharging || state==UIDeviceBatteryStateFull);
    if (stateChanged && state!=UIDeviceBatteryStateFull) dispatch_async(Work, ^{ Engine.reset(); });
    ReconcileTimer(connected);
    if (connected) Request();
    else { Diagnostic=@"OwnChargingETA(source=none,reason=disconnected,eta=none)"; Pending=NO; }
}
void LSGCOwnETAConfigure(BOOL enabled) {
    NSCAssert(NSThread.isMainThread,@"main-only configuration");
    if (!Work) Work=dispatch_queue_create("com.minis.own-charge-eta",DISPATCH_QUEUE_SERIAL);
    if (Enabled==enabled) { if (enabled) LSGCOwnETAObserve(); return; }
    Enabled=enabled; ++Generation; Text=nil; Pending=NO; LastState=LastPercent=-99;
    dispatch_async(Work, ^{ Engine.reset(); });
    if (!enabled) {
        ReconcileTimer(NO);
        if (PowerEvents) { CFRunLoopRemoveSource(CFRunLoopGetMain(),PowerEvents,kCFRunLoopCommonModes); CFRelease(PowerEvents); PowerEvents=NULL; }
        Diagnostic=@"OwnChargingETA(source=none,reason=disabled,eta=none)"; return;
    }
    if (!PowerEvents) {
        PowerEvents=IOPSNotificationCreateRunLoopSource(PowerChanged,NULL);
        if (PowerEvents) CFRunLoopAddSource(CFRunLoopGetMain(),PowerEvents,kCFRunLoopCommonModes);
    }
    UIDevice.currentDevice.batteryMonitoringEnabled=YES; LSGCOwnETAObserve();
}
NSString *LSGCOwnETAText(void) {
    if (!Enabled) return nil;
    if (Text && Monotonic()-TextStamp<=95) return Text;
    UIDevice *d=UIDevice.currentDevice; NSInteger p=LSGCBatteryPercent(d.batteryLevel);
    if (d.batteryState==UIDeviceBatteryStateFull) return @"已充满 · 100%";
    if (d.batteryState==UIDeviceBatteryStateCharging && p>=0) return [NSString stringWithFormat:@"正在学习 · %ld%%",(long)p];
    return nil;
}
NSString *LSGCOwnETADiagnostic(void) { return [Diagnostic copy]; }
