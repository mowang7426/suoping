#import <Foundation/Foundation.h>

/// Immutable, already validated output; only the main thread consumes it.
@interface LSGCJikanETASnapshot : NSObject
@property(nonatomic,readonly) NSInteger remainingSeconds;
@property(nonatomic,readonly) NSInteger targetPercent;
@property(nonatomic,readonly) NSTimeInterval timestamp;
@property(nonatomic,readonly) NSString *source;
@property(nonatomic,readonly) NSString *algorithm;
@property(nonatomic,readonly) uint64_t generation;
- (instancetype)initWithSeconds:(NSInteger)seconds target:(NSInteger)target timestamp:(NSTimeInterval)timestamp source:(NSString *)source algorithm:(NSString *)algorithm generation:(uint64_t)generation;
@end

#ifdef __cplusplus
extern "C" {
#endif

BOOL LSGCJikanETAEnabled(void);
NSString *LSGCJikanETASource(void);
LSGCJikanETASnapshot *LSGCJikanETACurrentSnapshot(void);
/// Main-thread lightweight getter only. Never starts Jikan or computes estimates.
void LSGCJikanETARefresh(BOOL charging);
/// Called only by the verified post-publication notification.
void LSGCJikanETAProducerPublished(BOOL charging);
NSString *LSGCJikanETAReport(void);
/// Invalidates stale results on unplug/disable/lock-screen generation changes.
void LSGCJikanETAInvalidate(void);

#ifdef __cplusplus
}
#endif
